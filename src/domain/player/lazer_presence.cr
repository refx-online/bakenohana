require "json"
require "redis"

require "../../persistence/repositories/user"
require "../../infrastructure/redis/redis_client"
require "../../state/player_session"
require "../../shared/constants/mode"
require "../../transport/protocol/packet_builders"

# Lazer -> stable presence.
#
# The mirror image of `PresenceBridge`, and the reason stable's player list held
# no lazer users.
#
# stable asks who is online with `USER_PRESENCE_REQUEST_ALL`, and
# `UserPresenceRequestAllPacket` answered it by iterating `PlayerSession` --
# bancho sessions only. A lazer player never has one: it speaks the v2 API and
# the SignalR hubs, so it is not in the registry and cannot be sent. Meanwhile
# `PresenceBridge` writes every stable presence *into* redis for lazer to read,
# so redis already holds the lazer half of the same picture. This reads it back.
#
# Both directions share one keyspace (`signalr:presence:{user_id}`) and one
# stored document shape, so this reads data that is already there rather than
# adding a second source of truth.
#
# Why synthesised packets instead of a `Player`
# --------------------------------------------
# `Packets.user_presence` takes a `Player`, and the tempting shortcut -- build
# one and call it -- would register a fake session in `PlayerSession`, which is
# what the packet loop iterates, what gets ghost-disconnected, and what gets
# relayed to other clients. So these take the fields they need as primitives and
# are built by dedicated packet builders instead.
module LazerPresence
  # bancho `action` byte, as `PlayerStatus` uses it.
  ACTION_IDLE     = 0_u8
  ACTION_PLAYING  = 1_u8
  ACTION_CHOOSING = 3_u8

  # lazer `UserActivity` **type names**, which is what the stored document
  # carries -- the union discriminator only exists on the wire, and redis holds
  # the named form because that is the shape both writers agree on.
  #
  # lazer's activity is far richer than a single bancho action byte, so this
  # collapses it: anything involving a map is "playing", anything involving an
  # editor is "choosing", everything else is idle. A slightly wrong verb is
  # cosmetic in the player list; a missing player is the bug worth avoiding.
  PLAYING_ACTIVITIES = [
    "InSoloGame",
    "InMultiplayerGame",
    "SpectatingMultiplayerGame",
    "InPlaylistGame",
    "PlayingDailyChallenge",
    "WatchingReplay",
    "SpectatingUser",
  ]

  CHOOSING_ACTIVITIES = [
    "EditingBeatmap",
    "ModdingBeatmap",
    "TestingBeatmap",
  ]

  # One lazer player, flattened into the fields a bancho packet needs.
  struct Online
    getter id : Int32
    getter username : String
    getter country_code : Int32
    getter priv : Int32
    getter mode : Gamemode
    getter action : UInt8
    getter map_id : Int32
    getter info_text : String
    getter global_rank : Int32

    def initialize(
      @id,
      @username,
      @country_code,
      @priv,
      @mode,
      @action,
      @map_id,
      @info_text,
      @global_rank
    )
    end
  end

  # Every lazer player online, minus anyone who also holds a bancho session --
  # one account logged into both clients would otherwise appear twice.
  #
  # SCAN rather than KEYS: this runs per presence request, and KEYS blocks the
  # redis server for the whole keyspace while it walks it. The keyspace here is
  # tiny, but the habit is worth keeping -- this shares a redis with the score
  # server.
  def self.online : Array(Online)
    found = [] of Online?
    r = RedisService.redis
    cursor = "0"

    loop do
      # `scan` hands back untyped values -- `RedisValue` is a union of
      # Nil/Int32/Int64/String/Array -- so narrow before use rather than trusting
      # a shape. It also strips the shard's own key namespace back off the keys,
      # which `get` then re-applies, so passing them straight through is right.
      reply = r.scan(cursor, match: PresenceBridge.key_pattern, count: 200)

      keys = reply[1]
      if keys.is_a?(Array)
        keys.each { |raw| found << build(r, raw) if raw.is_a?(String) }
      end

      next_cursor = reply[0]
      cursor = next_cursor.is_a?(String) ? next_cursor : "0"
      break if cursor == "0"
    end

    found.compact
  rescue ex
    # never let cross-client presence break a stable session
    rlog "lazer presence read failed: #{ex.message}", Ansi::LYELLOW
    [] of Online
  end

  private def self.build(r, raw_key : String) : Online?
    user_id = raw_key.split(":").last.to_i?

    # A stable session for the same account owns that row: PresenceBridge is
    # already writing it and PlayerSession is authoritative for it.
    return nil if user_id.nil?
    return nil if PlayerSession.get(id: user_id)

    stored = r.get(raw_key)
    return nil if stored.nil? || stored.empty?

    document = begin
      JSON.parse(stored)
    rescue ex
      rlog "lazer presence: unparseable document for #{user_id}: #{ex.message}", Ansi::LYELLOW
      return nil
    end

    # Both clients write into this keyspace and tag who they are. Without the
    # check a stable player's document would be relayed back to stable through
    # the lazer path whenever their bancho session is briefly absent (a restart,
    # or the gap before a reconnect re-registers), producing a duplicate row
    # built from the lazer view of their own state.
    return nil unless (document["client"]? || "").to_s == "lazer"

    activity = document["Activity"]?
    return nil unless activity.is_a?(Hash)

    # The key being present *is* the online signal: speedforce deletes it when a
    # lazer user goes offline, so there is no status field to re-check here.
    user = UserRepo.fetch_one(user_id)
    return nil if user.nil?

    mode = Gamemode.from_params(((activity["RulesetID"]? || 0).to_i % 4).to_u8, Mods::NOMOD)

    Online.new(
      user_id,
      user.name,
      country_code_for(user.country),
      user.priv,
      mode,
      action_for(activity),
      (activity["BeatmapID"]? || 0).to_i,
      title_for(activity),
      global_rank_for(user_id, mode)
    )
  end

  def self.action_for(activity : Hash) : UInt8
    kind = (activity["type"]? || "").to_s

    return ACTION_PLAYING if PLAYING_ACTIVITIES.includes?(kind)
    return ACTION_CHOOSING if CHOOSING_ACTIVITIES.includes?(kind)

    ACTION_IDLE
  end

  def self.title_for(activity : Hash) : String
    (activity["BeatmapDisplayTitle"]? || "").to_s[0, 80]
  end

  def self.country_code_for(code : String) : Int32
    # `xx` is the "unknown" value the geolocation service assigns.
    return 0 if code.nil? || code.empty? || code == "xx"
    code.to_u8.to_i32
  end

  def self.global_rank_for(user_id : Int32, mode : Gamemode) : Int32
    # Same source `Player#update_stats` uses: the rank lives in the redis
    # leaderboard, not in a stats row. zrevrank is 0-based, hence the +1.
    rank = RedisService.zrevrank(RedisService.leaderboard_key(mode.as_vn.to_i), user_id)
    rank ? (rank + 1).to_i32 : 0
  rescue
    0
  end
end
