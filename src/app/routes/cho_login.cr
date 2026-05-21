require "../objects/player"

require "../state/sessions"
require "../state/auth"

require "../packets/packets"

require "../models/login_data"
require "../models/osu_version"

require "../consts/priv"
require "../consts/login_response"

require "../repo/ingame_login"

require "../utils"
require "../log"

WELCOME_MESSAGE = %q(
        Welcome aboard.
        Running bakenohana v1.0.0
)

module Cho
  def self.parse_login(body : Bytes) : LoginData
    str = String.new(body)
    lines = str.split('\n', remove_empty: true)

    raise "login: not 3 lines" unless lines.size == 3

    username     = lines[0]
    password_md5 = lines[1]
    meta         = lines[2].split('|')

    raise "login: meta not 5+" unless meta.size >= 5

    osu_version  = meta[0]
    utc_offset   = meta[1].to_i
    display_city = meta[2] == "1"
    adapters_str = meta[3]
    pm_private   = meta[4] == "1"

    hwid_parts = adapters_str.split(':', remove_empty: true)

    raise "login: bad adapters" unless hwid_parts.size >= 5

    LoginData.new(
      username:            username,
      password_md5:        password_md5,
      osu_version:         osu_version,
      utc_offset:          utc_offset,
      display_city:        display_city,
      adapters_str:        adapters_str,
      osu_path_md5:        hwid_parts[0],
      adapters_md5:        hwid_parts[2],
      uninstall_md5:       hwid_parts[3],
      disk_signature_md5:  hwid_parts[4],
      pm_private:          pm_private
    )
  end

  def self.handle_login(env : HTTP::Server::Context, ip : String)
    begin
      body_content = env.request.body
      raise "empty body" if body_content.nil?

      body_bytes  = body_content.gets_to_end.to_slice
      login_data  = parse_login(body_bytes)
      login_time  = Time.utc

      if player = PlayerSession.get(username: login_data.username)
        if (login_time.to_unix - player.last_recv_time.to_unix) < 10
          env.response.headers["cho-token"] = "no"
          env.response.write(
            Packets.notification("user already logged in!") +
            Packets.login_reply(LoginResponse::AUTH_FAILED)
          )
          return
        else
          player.logout
        end
      end

      user_info = Auth.authenticate(login_data.username, login_data.password_md5)

      unless user_info
        env.response.headers["cho-token"] = "no"
        env.response.write(Packets.login_reply(LoginResponse::AUTH_FAILED))
        return
      end

      Auth.validate_adapters(user_info.id, login_data, ip)

      osu_token = Random::Secure.hex(16)
      player = Player.new(
        user_info.id,
        user_info.name,
        osu_token,
        ip,
        login_time,
        Privileges.new(user_info.priv),
        user_info.silence_end.to_i64
      )
      player.update_offset(login_data.utc_offset)
      PlayerSession.add(osu_token, player)

      if !player.restricted && !player.priv.includes?(Privileges::VERIFIED)
        player.add_priv(Privileges::VERIFIED)
      end

      player.load_stats
      player.update_leaderboards

      io = IO::Memory.new
      io.write Packets.login_reply(player.id)
      io.write Packets.protocol_version(19)
      io.write Packets.bancho_privileges((player.client_priv | ClientPrivileges::SUPPORTER).value)

      io.write Packets.notification(WELCOME_MESSAGE)

      user_data = Packets.user_presence(player) + Packets.user_stats(player)
      io.write user_data

      if !player.restricted
        PlayerSession.each do |p|
          next if p.pres_filter == PresenceFilter::Nil
          next if p.pres_filter == PresenceFilter::Friends && !p.friends.includes?(player.id)
          p.enqueue(user_data)
          unless p.restricted
            if p == PlayerSession.bot
              io.write Packets.bot_presence(p)
              io.write Packets.bot_stats(p)
            else
              io.write Packets.user_presence(p)
              io.write Packets.user_stats(p)
            end
          end
        end
      else
        PlayerSession.unrestricted.each do |p|
          if p == PlayerSession.bot
            io.write Packets.bot_presence(p)
            io.write Packets.bot_stats(p)
          else
            io.write Packets.user_presence(p)
            io.write Packets.user_stats(p)
          end
        end
        io.write Packets.account_restricted
        player.send_msg("yo bum ass is restricted", PlayerSession.bot)
      end

      ChannelSession.each do |c|
        next if !c.auto_join || !c.can_read?(player.priv) || c.r_name == "#lobby"

        chan_info_packet = Packets.channel_info(c.name, c.topic, c.player_count)
        io.write chan_info_packet

        PlayerSession.each do |o, _|
          o.enqueue(chan_info_packet) if c.can_read?(o.priv)
        end
      end

      io.write Packets.channel_info_end

      player.get_relationship
      io.write Packets.friends_list(player.friends)
      io.write Packets.silence_end(player.remaining_silence)

      if parsed_ver = OsuVersion.parse(login_data.osu_version)
        spawn IngameLoginRepo.create(player.id, ip, parsed_ver.date, parsed_ver.stream)
      end

      elap = (Time.utc - login_time).total_milliseconds
      rlog "#{player.username} (#{player.id}) logged in (#{elap.round(2)}ms)", Ansi::LCYAN

      env.response.headers["cho-token"] = osu_token
      env.response.status_code = 200
      env.response.write(io.to_slice)

    rescue ex
      rlog "[login err] #{ex.message}", Ansi::LRED
      rlog ex.backtrace.join("\n"), Ansi::LRED

      env.response.headers["cho-token"] = "invalid"
      env.response.status_code = 500
      env.response.write(
        Packets.notification("bad login packet") +
        Packets.login_reply(LoginResponse::ERROR_OCCUR)
      )
    end
  end
end
