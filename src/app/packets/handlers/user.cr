require "../../state/sessions"
require "../../consts/mods"
require "../../consts/mode"

class PongPacket < BasePacket
  def handle(p : Player)
  end
end

class LogoutPacket < BasePacket
  def handle(p : Player)
    return if Time.utc.to_unix - p.login_time.to_unix < 1
    p.logout
  end
end

class ChangeActionPacket < BasePacket
  def initialize(reader : BanchoPacketReader)
    super(reader)
    @action    = reader.read_u8
    @info_text = reader.read_string
    @map_md5   = reader.read_string
    @mods      = reader.read_u32
    @mode      = reader.read_u8
    @map_id    = reader.read_i32

    if (@mods & Mods::TOUCHSCREEN.value) != 0
      @mode = 20_u8
    elsif (@mods & Mods::RELAX.value) != 0
      if @mode == 3
        @mods &= ~Mods::RELAX.value
      elsif @mode <= 2
        @mode = (@mode + 4).to_u8
      elsif @mode > 6
        @mods &= ~Mods::RELAX.value
      end
    elsif (@mods & Mods::AUTOPILOT.value) != 0
      if @mode == 0
        @mode = 8_u8
      else
        @mods &= ~Mods::AUTOPILOT.value
      end
    end
  end

  def handle(p : Player) : Nil
    p.status.action    = @action
    p.status.map_md5   = @map_md5
    p.status.mods      = Mods.new(@mods)
    p.status.mode      = Gamemode.new(@mode)
    p.status.map_id    = @map_id

    tag = if (@mods & Mods::RELAX.value) != 0
      " [RX]"
    elsif (@mods & Mods::AUTOPILOT.value) != 0
      " [AP]"
    elsif (@mods & Mods::TOUCHSCREEN.value) != 0
      " [TD]"
    else
      " [VN]"
    end
    p.status.info_text = @info_text + tag

    p.enqueue(Packets.user_stats(p)) unless p.restricted
  end
end

class UserStatsRequestPacket < BasePacket
  def initialize(reader : BanchoPacketReader)
    super(reader)
    @user_ids = reader.read_i32_list_i16l
  end

  def handle(p : Player)
    unrestricted_ids = PlayerSession.unrestricted.map(&.id).to_set
    is_online = ->(id : Int32) { unrestricted_ids.includes?(id) && id != p.id }

    @user_ids.select(&is_online).each do |id|
      target = PlayerSession.get(id: id)
      next unless target

      packet = target == PlayerSession.bot ? Packets.bot_stats(target) : Packets.user_stats(target)
      p.enqueue(packet)
    end
  end
end

class UserPresenceRequestPacket < BasePacket
  def initialize(reader : BanchoPacketReader)
    super(reader)
    @user_ids = reader.read_i32_list_i16l
  end

  def handle(p : Player)
    @user_ids.each do |id|
      target = PlayerSession.get(id: id)
      next unless target
      p.enqueue(Packets.user_presence(target))
    end
  end
end

register(ClientPackets::PONG,                   PongPacket)
register(ClientPackets::LOGOUT,                 LogoutPacket)
register(ClientPackets::ACTION,                 ChangeActionPacket)
register(ClientPackets::USER_STATS,             UserStatsRequestPacket)
register(ClientPackets::USER_PRESENCE_REQUEST,  UserPresenceRequestPacket)

register_restricted(ClientPackets::PONG,                   PongPacket)
register_restricted(ClientPackets::LOGOUT,                 LogoutPacket)
register_restricted(ClientPackets::ACTION,                 ChangeActionPacket)
register_restricted(ClientPackets::USER_STATS,             UserStatsRequestPacket)
register_restricted(ClientPackets::USER_PRESENCE_REQUEST,  UserPresenceRequestPacket)
