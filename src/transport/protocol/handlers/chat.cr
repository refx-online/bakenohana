require "../../../state/player_session"
require "../../../state/channel_session"
require "../../../domain/player/commands/bot_commands"
require "../../../domain/match/commands/mp_commands"
require "../../../shared/value_objects/message"
require "../../../infrastructure/performance/performance_calculator"
require "../../../shared/constants/mods"

require "../../../infrastructure/config/config"

NP_REGEX = Regex.new(
  "^\\x01ACTION is (?:playing|editing|watching|listening to) " \
  "\\[https?://osu\\.(?:ppy\\.sh|#{Regex.escape(Config.domain)})/beatmapsets/(?<sid>\\d{1,10})#/?(?:osu|taiko|fruits|mania)?/(?<bid>\\d{1,10})"
)

class SendMessagePublicPacket < BasePacket
  def initialize(reader : BanchoPacketReader)
    super(reader)
    @msg = reader.read_message
  end

  def handle(p : Player)
    msg_text = @msg.text.strip
    return if msg_text.empty?

    if p.silenced?
      p.enqueue(Packets.notification("you are silenced and cannot send messages."))
      return
    end

    recipient = @msg.recipient

    t_chan = if recipient == "#spectator"
      spectated_id = p.spectating.try(&.id) || p.id
      ChannelSession["#spec_#{spectated_id}"]
    elsif recipient == "#multiplayer"
      m = p.match
      m ? ChannelSession["#multi_#{m.id}"] : nil
    else
      ChannelSession[recipient]
    end

    unless t_chan
      rlog "#{p.username} wrote to non-existent #{recipient}.", Ansi::LYELLOW
      return
    end

    unless t_chan.can_write?(p.priv)
      rlog "#{p.username} wrote to #{recipient} with insufficient privileges.", Ansi::LYELLOW
      return
    end

    if msg_text.size > 2000
      msg_text = "#{msg_text[0, 2000]}... (truncated)"
      p.enqueue(Packets.notification("Your message was truncated\n(exceeded 2000 characters)."))
    end

    if msg_text.starts_with?("!mp") && (m = p.match)
      MpCommandHandler.handle(p, m, msg_text)
      return
    end

    t_chan.send_msg(msg_text, sender: p)
  end
end

class SendMessagePrivatePacket < BasePacket
  def initialize(reader : BanchoPacketReader)
    super(reader)
    @msg = reader.read_message
  end

  def handle(p : Player)
    msg_text = @msg.text.strip
    return if msg_text.empty?

    if p.silenced?
      p.enqueue(Packets.notification("you are silenced and cannot send messages."))
      return
    end

    target = PlayerSession.get(username: @msg.recipient)

    unless target
      rlog "#{p.username} wrote to non-existent #{@msg.recipient}.", Ansi::LYELLOW
      return
    end

    if target == PlayerSession.bot
      if m = NP_REGEX.match(msg_text)
        map_id = m["bid"].to_i
        mode   = p.status.mode
        p.last_np = {map_id, mode}

        spawn do
          begin
            result = OsuPerformanceCalculator.calculate_score(map_id, mode)
            mods_str = conv_mods(p.status.mods)
            reply = "#{mods_str} | ★ #{result.stars.round(2)} | FC: #{result.pp.round(2)}pp"
            p.enqueue(Packets.send_message(PlayerSession.bot.username, reply, p.username, 1))
          rescue ex
            p.enqueue(Packets.send_message(PlayerSession.bot.username, "couldn't calculate: #{ex.message}", p.username, 1))
          end
        end
        return
      end

      return CommandHandler.handle_command(p, msg_text) if msg_text.starts_with?(Config.boat_prefix)
      return
    end

    if target.silenced?
      p.enqueue(Packets.target_is_silenced(target.username))
      return
    end

    if target.pm_private && !target.friends.includes?(p.id)
      p.enqueue(Packets.user_dm_blocked(target.username))
      return
    end

    if msg_text.size > 2000
      msg_text = "#{msg_text[0, 2000]}... (truncated)"
      p.enqueue(Packets.notification("Your message was truncated\n(exceeded 2000 characters)."))
    end

    if away = target.away_msg
      p.enqueue(Packets.send_message(target.username, "[away] #{away}", p.username, target.id))
    end

    target.send_msg(msg_text, sender: p)
  end
end

class JoinChannelPacket < BasePacket
  def initialize(reader : BanchoPacketReader)
    super(reader)
    @name = reader.read_string
  end

  def handle(p : Player)
    return if ["#highlight", "#userlog"].includes?(@name)

    channel = ChannelSession[@name]
    if channel.nil? || !p.join_channel(channel)
      rlog "#{p.username} failed to join #{@name}.", Ansi::LYELLOW
    end
  end
end

register(ClientPackets::SEND_PUBLIC_MESSAGE,  SendMessagePublicPacket)
register(ClientPackets::SEND_PRIVATE_MESSAGE, SendMessagePrivatePacket)
register(ClientPackets::CHANNEL_JOIN,         JoinChannelPacket)
