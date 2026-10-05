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

  rlog "hop on localhost:#{ENV["PORT"]? || "3000"}", Ansi::LBLUE
  Kemal.run
end
