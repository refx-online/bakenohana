require "../../domain/player/player"
require "../../shared/value_objects/score_frame"
require "../../shared/value_objects/multi_match"
require "./packets"

enum ClientPackets : UInt16
  ACTION                    = 0
  SEND_PUBLIC_MESSAGE       = 1
  LOGOUT                    = 2
  REQUEST_STATUS_UPDATE     = 3
  PONG                      = 4
  START_SPECTATING          = 16
  STOP_SPECTATING           = 17
  SPECTATE_FRAMES           = 18
  ERROR_REPORT              = 20
  CANT_SPECTATE             = 21
  SEND_PRIVATE_MESSAGE      = 25
  PART_LOBBY                = 29
  JOIN_LOBBY                = 30
  CREATE_MATCH              = 31
  JOIN_MATCH                = 32
  PART_MATCH                = 33
  MATCH_CHANGE_SLOT         = 38
  MATCH_READY               = 39
  MATCH_LOCK                = 40
  MATCH_CHANGE_SETTINGS     = 41
  MATCH_START               = 44
  MATCH_SCORE_UPDATE        = 47
  MATCH_COMPLETE            = 49
  MATCH_CHANGE_MODS         = 51
  MATCH_LOAD_COMPLETE       = 52
  MATCH_NO_BEATMAP          = 54
  MATCH_NOT_READY           = 55
  MATCH_FAILED              = 56
  MATCH_HAS_BEATMAP         = 59
  MATCH_SKIP_REQUEST        = 60
  CHANNEL_JOIN              = 63
  MATCH_TRANSFER_HOST       = 70
  FRIEND_ADD                = 73
  FRIEND_REMOVE             = 74
  MATCH_CHANGE_TEAM         = 77
  CHANNEL_PART              = 78
  RECEIVE_UPDATES           = 79
  SET_AWAY_MESSAGE          = 82
  USER_STATS                = 85
  MATCH_INVITE              = 87
  MATCH_CHANGE_PASSWORD     = 90
  USER_PRESENCE_REQUEST     = 97
  USER_PRESENCE_REQUEST_ALL = 98
  TOGGLE_BLOCK_NON_FRIEND_DMS = 99
  REFX_LB                     = 138
end

abstract class BasePacket
  def initialize(@reader : BanchoPacketReader)
  end

  abstract def handle(p : Player)
end

alias PacketMap = Hash(UInt16, BasePacket.class)

macro register(packet_id, packet_class)
  PACKET_MAP[{{packet_id}}.to_u16] = {{packet_class}}
end

macro register_restricted(packet_id, packet_class)
  RESTRICTED_PACKET_MAP[{{packet_id}}.to_u16] = {{packet_class}}
end

PACKET_MAP            = PacketMap.new
RESTRICTED_PACKET_MAP = PacketMap.new

class BanchoPacketReader
  include Iterator(BasePacket)

  @body_view : Bytes
  @packet_map : PacketMap
  @current_len : Int32 = 0

  def initialize(body_view : Bytes, @packet_map : PacketMap)
    @body_view = body_view
  end

  def next
    while @body_view.size >= 7
      p_type, p_len = read_header

      if packet_class = @packet_map[p_type]?
        @current_len = p_len
        return packet_class.new(self)
      else
        if p_len != 0 && p_len <= @body_view.size
          @body_view = @body_view[p_len..]
        else
          break
        end
      end
    end
    stop
  end

  private def read_header : {UInt16, Int32}
    raise IndexError.new("not enough data for header") if @body_view.size < 7

    packet_id = @body_view[0].to_u16 | (@body_view[1].to_u16 << 8)
    packet_len = @body_view[3].to_u32 |
                (@body_view[4].to_u32 << 8) |
                (@body_view[5].to_u32 << 16) |
                (@body_view[6].to_u32 << 24)

    @body_view = @body_view[7..]
    {packet_id, packet_len.to_i}
  end

  def read_raw : Bytes
    raise IndexError.new("not enough data") if @current_len > @body_view.size
    val = @body_view[0, @current_len]
    @body_view = @body_view[@current_len..]
    val
  end

  def read_i8 : Int8
    raise IndexError.new("not enough data") if @body_view.size < 1
    val = @body_view[0]
    @body_view = @body_view[1..]
    val > 127 ? (val - 256).to_i8 : val.to_i8
  end

  def read_u8 : UInt8
    raise IndexError.new("not enough data") if @body_view.size < 1
    val = @body_view[0]
    @body_view = @body_view[1..]
    val
  end

  def read_i16 : Int16
    raise IndexError.new("not enough data") if @body_view.size < 2
    val = @body_view[0].to_i16 | (@body_view[1].to_i16 << 8)
    @body_view = @body_view[2..]
    val > 32767 ? (val - 65536).to_i16 : val
  end

  def read_u16 : UInt16
    raise IndexError.new("not enough data") if @body_view.size < 2
    val = @body_view[0].to_u16 | (@body_view[1].to_u16 << 8)
    @body_view = @body_view[2..]
    val
  end

  def read_i32 : Int32
    raise IndexError.new("not enough data") if @body_view.size < 4
    val = @body_view[0].to_i32 |
          (@body_view[1].to_i32 << 8) |
          (@body_view[2].to_i32 << 16) |
          (@body_view[3].to_i32 << 24)
    @body_view = @body_view[4..]
    val
  end

  def read_u32 : UInt32
    raise IndexError.new("not enough data") if @body_view.size < 4
    val = @body_view[0].to_u32 |
          (@body_view[1].to_u32 << 8) |
          (@body_view[2].to_u32 << 16) |
          (@body_view[3].to_u32 << 24)
    @body_view = @body_view[4..]
    val
  end

  def read_i64 : Int64
    raise IndexError.new("not enough data") if @body_view.size < 8
    val = @body_view[0].to_i64 |
          (@body_view[1].to_i64 << 8) |
          (@body_view[2].to_i64 << 16) |
          (@body_view[3].to_i64 << 24) |
          (@body_view[4].to_i64 << 32) |
          (@body_view[5].to_i64 << 40) |
          (@body_view[6].to_i64 << 48) |
          (@body_view[7].to_i64 << 56)
    @body_view = @body_view[8..]
    val
  end

  def read_u64 : UInt64
    raise IndexError.new("not enough data") if @body_view.size < 8
    val = @body_view[0].to_u64 |
          (@body_view[1].to_u64 << 8) |
          (@body_view[2].to_u64 << 16) |
          (@body_view[3].to_u64 << 24) |
          (@body_view[4].to_u64 << 32) |
          (@body_view[5].to_u64 << 40) |
          (@body_view[6].to_u64 << 48) |
          (@body_view[7].to_u64 << 56)
    @body_view = @body_view[8..]
    val
  end

  def read_f32 : Float32
    raise IndexError.new("not enough data") if @body_view.size < 4
    val = IO::Memory.new(@body_view[0, 4]).read_bytes(Float32, IO::ByteFormat::LittleEndian)
    @body_view = @body_view[4..]
    val
  end

  def read_f64 : Float64
    raise IndexError.new("not enough data") if @body_view.size < 8
    val = IO::Memory.new(@body_view[0, 8]).read_bytes(Float64, IO::ByteFormat::LittleEndian)
    @body_view = @body_view[8..]
    val
  end

  def read_i32_list_i16l : Array(Int32)
    len = read_u16.to_i
    arr = Array(Int32).new(len)
    len.times { arr << read_i32 }
    arr
  end

  def read_i32_list_i32l : Array(Int32)
    len = read_u32.to_i
    arr = Array(Int32).new(len)
    len.times { arr << read_i32 }
    arr
  end

  def read_string : String
    exists = read_u8 == 0x0B
    return "" unless exists

    len = 0
    shift = 0

    loop do
      byte = read_u8
      len |= (byte & 0x7F) << shift
      break unless (byte & 0x80) != 0
      shift += 7
    end

    str_bytes = @body_view[0, len]
    @body_view = @body_view[len..]
    String.new(str_bytes)
  end

  def read_message : Message
    Message.new(
      read_string(),
      read_string(),
      read_string(),
      read_i32()
    )
  end

  def read_channel : Chan
    Chan.new(
      read_string(),
      read_string(),
      read_i32()
    )
  end

  def read_match : MultiMatch
    m = MultiMatch.new
    m.id           = read_i16
    m.in_progress  = read_i8 == 1_i8
    m.powerplay    = read_i8
    m.mods         = read_i32
    m.name         = read_string
    m.passwd       = read_string
    m.map_name     = read_string
    m.map_id       = read_i32
    m.map_md5      = read_string

    m.slot_statuses = Array(Int8).new(16) { read_i8 }
    m.slot_teams    = Array(Int8).new(16) { read_i8 }

    m.slot_statuses.each do |status|
      if (status & 0b01111100) != 0
        m.slot_ids << read_i32
      end
    end

    m.host_id      = read_i32
    m.mode         = read_i8
    m.win_condition = read_i8
    m.team_type    = read_i8
    m.freemods     = read_i8 == 1_i8

    if m.freemods
      m.slot_mods = Array(Int32).new(16) { read_i32 }
    end

    m.seed = read_i32
    m
  end

  def read_scoreframe : ScoreFrame
    sf = ScoreFrame.new
    sf.time          = read_i32
    sf.id            = read_i8.to_i32
    sf.num300        = read_u16
    sf.num100        = read_u16
    sf.num50         = read_u16
    sf.num_geki      = read_u16
    sf.num_katu      = read_u16
    sf.num_miss      = read_u16
    sf.total_score   = read_i32
    sf.max_combo     = read_u16
    sf.current_combo = read_u16
    sf.perfect       = read_u8 == 1_u8
    sf.current_hp    = read_u8
    sf.tag_byte      = read_u8
    sf.score_v2      = read_u8 == 1_u8
    if sf.score_v2
      sf.combo_portion = read_f64
      sf.bonus_portion = read_f64
    end
    sf
  end
end

require "./handlers/user"
require "./handlers/chat"
require "./handlers/social"
require "./handlers/spectate"
require "./handlers/misc"
require "./handlers/match"
