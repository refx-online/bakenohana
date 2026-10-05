require "json"
require "redis"
require "../../infrastructure/config/config"
require "../../infrastructure/redis/redis_client"

# Cross-client presence.
#
# bakenohana is the only thing that knows whether a *stable* player is online --
# its sessions live in the in-memory PlayerSession registry, which nothing else
# can read. speedforce serves the lazer metadata hub and keeps its own presence
# under `signalr:presence:*`, so without this a stable player is invisible to a
# lazer client and vice versa.
#
# Contract (both sides must agree):
#
#   key    signalr:presence:{user_id}
#   value  JSON, whatever the client understands -- see `document` below
#   ttl    90s, refreshed on every status packet
#
# Writes are deliberately cheap: two redis commands on login/logout and one
# SETEX per status packet. Nothing here is load-bearing for stable itself, so a
# redis failure must never break a stable session -- every call is rescued.
#
# TTL rather than a delete on logout is the safety net: a crashed bakenohana
# leaves keys that expire on their own instead of showing phantom online users.
module PresenceBridge
  # must match speedforce's PRESENCE_TTL_SECONDS
  TTL_SECONDS = 90

  # channel speedforce subscribes to for "a stable presence changed"
  CHANNEL = "signalr:presence_changed"

  # lazer UserActivity union discriminators (osu.Game/Users/UserActivity.cs).
  # stable has no activity concept of its own, so we map its `action` onto the
  # nearest lazer shape:
  #   0 idle, 1 playing, 2 afk  -> ChoosingBeatmap / InSoloGame
  #   3 choosing                 -> ChoosingBeatmap
  # stable's status packet can also carry an info_text (e.g. "Selecting Beatmap"),
  # which we pass through verbatim so lazer renders something meaningful.
  ACTION_IDLE      = 0
  ACTION_PLAYING   = 1
  ACTION_AFK       = 2
  ACTION_CHOOSING  = 3

  def self.key(user_id : Int32) : String
    "signalr:presence:#{user_id}"
  end

  # Build the JSON document lazer's metadata hub relays.
  def self.document(player) : String
    status = player.status

    activity =
      case status.action
      when ACTION_PLAYING
        {
          "type"             => "InSoloGame",
          "BeatmapID"        => status.map_id,
          "RulesetID"        => status.mode.value % 4,
          "BeatmapDisplayTitle" => status.info_text,
        }
      else
        {"type" => "ChoosingBeatmap"}
      end

    # lazer's UserPresence is `{ Activity, Status }` where
    #
    #   [MessagePackObject] struct UserPresence {
    #       [Key(0)] UserActivity? Activity;
    #       [Key(1)] UserStatus?   Status;    // Offline=0, DoNotDisturb=1, Online=2
    #   }
    #
    # `Status` is the *enum*, not an object. It used to be written as
    # `{ "Status": "Idle", "BeatmapInfo": {...}, "RankedMods": [] }`, which is
    # some other shape entirely -- speedforce's `presence_to_client` does
    # `_STATUS_ORDINALS.get(status)` by name, so a dict never matched and the
    # presence was silently dropped. lazer's own online list would have been
    # empty for the same reason.
    #
    # speedforce maps this name to the ordinal on the way out; the stored form is
    # JSON by contract (see the header comment).
    JSON.build do |json|
      json.object do
        json.field "Activity", activity
        json.field "Status", "Online"
        json.field "rulesetId", status.mode.value % 4
        json.field "client", "stable"
      end
    end
  end

  def self.set_presence(player) : Nil
    r = RedisService.redis
    r.setex(key(player.id), TTL_SECONDS, document(player))
    r.publish(CHANNEL, player.id.to_s)
    nil
  rescue ex
    # never let presence break a stable session
    rlog "presence set failed for #{player.id}: #{ex.message}", Ansi::LYELLOW
    nil
  end

  def self.clear_presence(user_id : Int32) : Nil
    r = RedisService.redis
    r.del(key(user_id))
    r.publish(CHANNEL, user_id.to_s)
    nil
  rescue ex
    rlog "presence clear failed for #{user_id}: #{ex.message}", Ansi::LYELLOW
    nil
  end

  # status packets arrive ~1/s while a player is online; only write when
  # something a watcher can see actually changed.
  def self.touch(player, prev_action, prev_map_id, prev_mode) : Nil
    status = player.status
    return if status.action == prev_action &&
              status.map_id == prev_map_id &&
              status.mode.value == prev_mode
    set_presence(player)
  end
end