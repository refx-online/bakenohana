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

  spawn do
    loop do
      sleep OSU_CLIENT_MIN_PING_INTERVAL // 3
      now = Time.utc
      PlayerSession.each do |player, _token|
        next if player.id == 1
        if (now - player.last_recv_time).total_seconds > OSU_CLIENT_MIN_PING_INTERVAL
          rlog "Auto-dced #{player.username} (ghost).", Ansi::LMAGENTA
          player.logout
        end
      end
    end
  end

  rlog "hop on localhost:#{ENV["PORT"]? || "3000"}", Ansi::LBLUE
  Kemal.run
end
