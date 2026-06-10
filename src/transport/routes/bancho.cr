require "./get"

require "../../domain/player/player"

require "../../state/player_session"

require "../protocol/packets"
require "../protocol/reader"
require "../protocol/handlers/login"

require "../../persistence/repositories/user"

require "../../shared/helpers/country_codes"
require "../../infrastructure/logging/logger"

module Cho
  def self.register_routes
    post "/" do |env|
      next env.response.status_code = 403 if env.request.headers["User-Agent"]? != "osu!"

      ip = (
        env.request.headers["CF-Connecting-IP"]? ||
        env.request.headers["X-Forwarded-For"]?.try(&.split(',')[0]?) ||
        ""
      )
      token = env.request.headers["osu-token"]?

      if token.nil?
        LoginEvent.handle(env, ip)
        next
      end

      player = PlayerSession.get(token)
      if player.nil?
        env.response.write(
          Packets.notification("server restarted") + Packets.restart_server(0)
        )
        next
      end

      body_content = env.request.body
      next if body_content.nil?

      body = body_content.gets_to_end.to_slice
      packet_map = player.restricted ? RESTRICTED_PACKET_MAP : PACKET_MAP

      begin
        BanchoPacketReader.new(body, packet_map).each do |packet|
          rlog "Player #{player.username} sent #{packet.class.name}", Ansi::LBLUE
          packet.handle(player)
        end
      rescue ex
        rlog "[packet] #{ex.message}", Ansi::LRED
        rlog ex.backtrace.join("\n"), Ansi::LRED
        next env.response.write(player.dequeue)
      end

      player.last_recv_time = Time.utc
      spawn UserRepo.update(player.id, latest_activity: Time.utc.to_unix.to_i32)
      env.response.write(player.dequeue)
    end

    register_get
  end
end
