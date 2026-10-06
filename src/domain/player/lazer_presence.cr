require "json"
require "redis"

require "../../persistence/repositories/user"
require "../../infrastructure/redis/redis_client"
require "../../state/player_session"
require "../../shared/constants/mode"
require "../../shared/helpers/country_codes"
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
      keys.each { |raw| found << build(r, raw) if raw.is_a?(String) } if keys.is_a?(Array)

      next_cursor = reply[0]
      cursor = next_cursor.is_a?(String) ? next_cursor : "0"
      break if cursor == "0"
    end

    resolved = found.compact
    if resolved.empty?
      rlog "lazer presence: no lazer players online (no #{PresenceBridge.key_pattern} keys resolved)", Ansi::LYELLOW
    end
    resolved
  rescue ex
    # never let cross-client presence break a stable session
    rlog "lazer presence read failed: #{ex.message}", Ansi::LYELLOW
    [] of Online
  end

  private def self.build(r, raw_key : String) : Online?
    user_id = raw_key.split(":").last.to_i?
    return nil if user_id.nil?

    # A stable session for the same account owns that row: PresenceBridge is
    # already writing it and PlayerSession is authoritative for it.
    if session = PlayerSession.get(id: user_id)
      note(raw_key, "has a bancho session (#{session.username})")
      return nil
    end

    stored = r.get(raw_key)
    return nil if stored.nil? || stored.empty?

    document = parse(raw_key, stored)
    if document.nil?
      return nil
    end

    # Both clients write into this keyspace and tag who they are. Without the
    # check a stable player's document would be relayed back to stable through
    # the lazer path whenever their bancho session is briefly absent (a restart,
    # or the gap before a reconnect re-registers), producing a duplicate row
    # built from the lazer view of their own state.
    tag = (document["client"]? || "").to_s
    if tag != "lazer"
      note(raw_key, "client tag is #{tag.inspect}, want \"lazer\"")
      return nil
    end

    activity = document["Activity"]?.try(&.as_h?)
    if activity.nil?
      note(raw_key, "Activity is not an object")
      return nil
    end

    # The key being present *is* the online signal: speedforce deletes it when a
    # lazer user goes offline, so there is no status field to re-check here.
    user = UserRepo.fetch_one(user_id)
    if user.nil?
      note(raw_key, "no users row for #{user_id}")
      return nil
    end

    mode = Gamemode.from_params((int_at(activity, "RulesetID") % 4).to_u8, Mods::NOMOD)

    online = Online.new(
      user_id,
      user.name,
      country_code_for(user.country),
      user.priv,
      mode,
      action_for(activity),
      int_at(activity, "BeatmapID"),
      title_for(activity),
      global_rank_for(user_id, mode)
    )
    online
  end

  # Parsing lives in its own method so `build` gets a plain `JSON::Any?` back
  # rather than a `JSON::Any | Nil` union: a `begin/rescue` whose rescue path ends
  # in a conditional `return` widens the whole expression to Nil, and every later
  # `document[...]` then fails to compile.
  private def self.parse(raw_key, stored) : JSON::Any?
    JSON.parse(stored)
  rescue ex
    note(raw_key, "unparseable document: #{ex.message}")
    nil
  end

  # Every skip is logged. A silently-empty result is exactly the failure mode
  # that cost a round here: `country_code_for` once raised on a two-letter code,
  # the rescue swallowed it, and lazer players were dropped over a flag nobody
  # could see. Being skipped is normal (a bancho session owns that row); being
  # skipped *unexpectedly* must be visible.
  def self.note(raw_key, reason) : Nil
    rlog "lazer presence: skipping #{raw_key} -- #{reason}", Ansi::LYELLOW
  end

  # JSON values are `JSON::Any`, so every read needs an explicit conversion
  # rather than a bare `.to_i`, and a missing key has to read as a sane default
  # rather than raising -- a presence document is not worth failing a stable
  # session over.
  private def self.int_at(activity : Hash(String, JSON::Any), key : String) : Int32
    activity[key]?.try(&.as_i?).try(&.to_i32) || 0_i32
  end

  private def self.str_at(activity : Hash(String, JSON::Any), key : String) : String
    activity[key]?.try(&.as_s?) || ""
  end

  def self.action_for(activity : Hash(String, JSON::Any)) : UInt8
    kind = str_at(activity, "type")

    return ACTION_PLAYING if PLAYING_ACTIVITIES.includes?(kind)
    return ACTION_CHOOSING if CHOOSING_ACTIVITIES.includes?(kind)

    ACTION_IDLE
  end

  def self.title_for(activity : Hash(String, JSON::Any)) : String
    str_at(activity, "BeatmapDisplayTitle")[0, 80]
  end

  # `users.country` holds the two-letter code ("id", "us"), while bancho's
  # USER_PRESENCE country byte wants the numeric id. `"id".to_u8` raises
  # `Invalid UInt8`, which the rescue above swallowed into an empty list -- so
  # lazer players were dropped over a flag nobody could see. `COUNTRY_CODES` is
  # the same table the geolocation service uses.
  def self.country_code_for(code : String) : Int32
    COUNTRY_CODES[code.downcase]? || COUNTRY_CODES["xx"]
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
