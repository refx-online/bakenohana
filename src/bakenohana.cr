require "kemal"
require "dotenv"
Dotenv.load

require "./infrastructure/config/config"
require "./infrastructure/logging/logger"
require "./infrastructure/middleware/metrics"

require "./transport/routes/bancho"
require "./transport/routes/api"

require "./persistence/services"
require "./state/player_session"
require "./state/channel_session"
require "./infrastructure/redis/redis_client"
require "./messaging/pubsub_handler"
require "./state/match_session"
require "./domain/match/presence_bridge"
require "./domain/player/lazer_presence"
require "./shared/constants/presence_filter"

Services.init
RedisService.init
ChannelSession.prepare
PubSub.start

module Bakenohana
  Log.setup do |c|
    c.bind "kemal", Log::Severity::None, Log::IOBackend.new(IO::Memory.new)
  end
  Kemal.config.logging = false
  Kemal.config.add_handler Metrics.new

  if port_str = ENV["PORT"]?
    Kemal.config.port = port_str.to_i
  end

  Cho.register_routes
  Api::V1.register_routes

  OSU_CLIENT_MIN_PING_INTERVAL = 300

  # Presence keys expire after PresenceBridge::TTL_SECONDS (90s), so the refresh
  # has to happen comfortably inside that window. This used to tick every 100s --
  # slower than the TTL it was meant to keep alive, which is another way the
  # stable -> lazer presence list stayed empty.
  HOUSEKEEPING_INTERVAL = 30

  # How often to tell already-connected clients about lazer players they do not
  # know about yet. A client that logs in gets the full list in its burst, so this
  # only covers players who came online afterwards.
  LAZER_ANNOUNCE_INTERVAL = 15

  # Lazer user ids already announced to the connected clients.
  announced_lazer = Set(Int32).new

  spawn do
    loop do
      sleep HOUSEKEEPING_INTERVAL
      now = Time.utc
      PlayerSession.each do |player, _token|
        next if player.id == 1
        if (now - player.last_recv_time).total_seconds > OSU_CLIENT_MIN_PING_INTERVAL
          rlog "Auto-dced #{player.username} (ghost).", Ansi::LMAGENTA
          player.logout
        else
          # still talking to us, so keep their lazer-visible presence alive
          PresenceBridge.keepalive(player)
        end
      end
    end
  end

  # stable's online-users list only ever grows through unsolicited USER_PRESENCE
  # packets -- there is no request for it (USER_PRESENCE_REQUEST_ALL is the
  # spectator list) -- so a lazer player who comes online after a stable client
  # logged in has to be announced explicitly.
  spawn do
    loop do
      sleep LAZER_ANNOUNCE_INTERVAL

      begin
        LazerPresence.online.each do |user|
          next if announced_lazer.includes?(user.id)
          announced_lazer.add(user.id)

          PlayerSession.unrestricted.each do |other|
            next if other.id == 1
            next if other.pres_filter == PresenceFilter::Nil
            next if other.pres_filter == PresenceFilter::Friends # no friend graph to check
            other.enqueue(Packets.lazer_stats(user) + Packets.lazer_presence(user))
          end
        end
      rescue ex
        # never let cross-client presence break a stable session
        rlog "lazer announce failed: #{ex.message}", Ansi::LYELLOW
      end
    end
  end

  rlog "hop on localhost:#{ENV["PORT"]? || "3000"}", Ansi::LBLUE
  Kemal.run
end
