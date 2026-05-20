require "kemal"
require "dotenv"
Dotenv.load

require "./app/config"
require "./app/log"
require "./app/middleware"

require "./app/routes/bancho"

require "./app/state/services"
require "./app/state/sessions"
require "./app/state/redis"
require "./app/state/pubsub"

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

  rlog "hop on localhost:#{ENV["PORT"]? || "3000"}", Ansi::LBLUE
  Kemal.run
end
