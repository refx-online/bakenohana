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
  end

  def handle(p : Player) : Nil
    prev_mode = p.status.mode

    mode, mods = p.resolve_mode(@mode, @mods)

    tag = case mode
    when 4..7   then " [RX]"
    when 8      then " [AP]"
    when 12..15 then " [CHEAT]"
    when 16..19 then " [CHEATCHEAT]"
    when 20     then " [TD]"
    else             " [VN]"
    end

    p.status.action    = @action
    p.status.map_md5   = @map_md5
    p.status.mods      = Mods.new(mods)
    p.status.mode      = Gamemode.new(mode)
    p.status.map_id    = @map_id
    p.status.info_text = @info_text + tag

    if p.status.mode != prev_mode
      p.load_stats
      p.update_leaderboards
    end

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
