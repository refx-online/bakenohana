require "../../state/sessions"
require "../../consts/presence_filter"

class RequestStatusUpdatePacket < BasePacket
  def handle(p : Player)
    p.enqueue(Packets.user_stats(p))
  end
end

class ReceiveUpdatesPacket < BasePacket
  def initialize(reader : BanchoPacketReader)
    super(reader)
    @value = reader.read_i32
  end

  def handle(p : Player)
    unless (0..2).includes?(@value)
      rlog "#{p.username} tried to set presence filter to #{@value}?", Ansi::LYELLOW
      return
    end
    p.pres_filter = PresenceFilter.new(@value)
  end
end

class UserPresenceRequestAllPacket < BasePacket
  def initialize(reader : BanchoPacketReader)
    super(reader)
    reader.read_i32 # ingame_time, unused
  end

  def handle(p : Player)
    return if p.pres_filter == PresenceFilter::Nil

    PlayerSession.unrestricted.each do |other|
      next if p.pres_filter == PresenceFilter::Friends && !p.friends.includes?(other.id)
      p.enqueue(
        other == PlayerSession.bot ? Packets.bot_presence(other) : Packets.user_presence(other)
      )
    end
  end
end

class ChannelPartPacket < BasePacket
  def initialize(reader : BanchoPacketReader)
    super(reader)
    @name = reader.read_string
  end

  def handle(p : Player)
    return if ["#highlight", "#userlog"].includes?(@name)

    channel = ChannelSession[@name]
    unless channel
      rlog "#{p.username} failed to leave #{@name}.", Ansi::LYELLOW
      return
    end

    return unless channel.includes?(p)
    p.leave_channel(channel)
  end
end

class ToggleBlockNonFriendDMsPacket < BasePacket
  def initialize(reader : BanchoPacketReader)
    super(reader)
    @value = reader.read_i32
  end

  def handle(p : Player)
    p.pm_private = @value == 1
  end
end

class SetAwayMessagePacket < BasePacket
  def initialize(reader : BanchoPacketReader)
    super(reader)
    @msg = reader.read_message
  end

  def handle(p : Player)
    p.away_msg = @msg.text.empty? ? nil : @msg.text
  end
end

class ErrorReportPacket < BasePacket
  def initialize(reader : BanchoPacketReader)
    super(reader)
    @error = reader.read_string
  end

  def handle(p : Player)
    rlog "[client error] #{p.username}: #{@error}", Ansi::LYELLOW
  end
end

register(ClientPackets::REQUEST_STATUS_UPDATE,      RequestStatusUpdatePacket)
register(ClientPackets::ERROR_REPORT,              ErrorReportPacket)
register(ClientPackets::RECEIVE_UPDATES,           ReceiveUpdatesPacket)
register(ClientPackets::USER_PRESENCE_REQUEST_ALL, UserPresenceRequestAllPacket)
register(ClientPackets::CHANNEL_PART,              ChannelPartPacket)
register(ClientPackets::TOGGLE_BLOCK_NON_FRIEND_DMS, ToggleBlockNonFriendDMsPacket)
register(ClientPackets::SET_AWAY_MESSAGE,          SetAwayMessagePacket)

register_restricted(ClientPackets::REQUEST_STATUS_UPDATE,      RequestStatusUpdatePacket)
register_restricted(ClientPackets::RECEIVE_UPDATES,            ReceiveUpdatesPacket)
register_restricted(ClientPackets::USER_PRESENCE_REQUEST_ALL,  UserPresenceRequestAllPacket)
