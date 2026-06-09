require "./packet_types"
require "../../domain/match/match"
require "../../shared/value_objects/score_frame"

module Packets
  def self.write(packet_id : ServerPacket, *args : Tuple) : Bytes
    ret = Bytes.new(3)
    ret[0] = (packet_id.value & 0xFF).to_u8
    ret[1] = ((packet_id.value >> 8) & 0xFF).to_u8
    ret[2] = 0x00_u8

    payload_io = IO::Memory.new

    args.each do |arg|
        typed = arg.as(Tuple)
        value = typed[0]
        typ = typed[1].as(OsuType)

      case typ
      when OsuType::Raw
        slice = case value
                when String
                  value.to_slice
                when Bytes
                  value
                else
                  raise "expected bytes or string for OsuType::Raw, got #{value.class}"
                end
        payload_io.write slice

      when OsuType::I8
        payload_io.write_bytes(value.as?(Int8) || raise("expected int8"))

      when OsuType::U8
        payload_io.write_bytes(value.as?(UInt8) || raise("expected uint8"))

      when OsuType::I16
        payload_io.write_bytes(
          value.as?(Int16) || raise("expected int16"),
          IO::ByteFormat::LittleEndian
        )

      when OsuType::U16
        payload_io.write_bytes(
          value.as?(UInt16) || raise("expected uint16"),
          IO::ByteFormat::LittleEndian
        )

      when OsuType::I32
        payload_io.write_bytes(
          value.as?(Int32) || raise("expected int32"),
          IO::ByteFormat::LittleEndian
        )

      when OsuType::U32
        payload_io.write_bytes(
          value.as?(UInt32) || raise("expected uint32"),
          IO::ByteFormat::LittleEndian
        )

      when OsuType::I64
        payload_io.write_bytes(
          value.as?(Int64) || raise("expected int64"),
          IO::ByteFormat::LittleEndian
        )

      when OsuType::U64
        payload_io.write_bytes(
          value.as?(UInt64) || raise("expected uint64"),
          IO::ByteFormat::LittleEndian
        )

      when OsuType::F32
        payload_io.write_bytes(
          value.as?(Float32) || raise("expected float32"),
          IO::ByteFormat::LittleEndian
        )

      when OsuType::F64
        payload_io.write_bytes(
          value.as?(Float64) || raise("expected float64"),
          IO::ByteFormat::LittleEndian
        )

      when OsuType::String
        write_string payload_io, value.to_s

      when OsuType::I32List
        write_i32_list payload_io, value.as?(Array(Int32)) || raise("expected array(int32)")

      when OsuType::Message
        write_message payload_io, value.as?(Tuple(String, String, String, Int32)) || raise("expected message tuple")

      when OsuType::Channel
        write_channel payload_io, value.as?(Tuple(String, String, Int32)) || raise("expected channel tuple")

      when OsuType::Match
        tup = value.as?(Tuple(Match, Bool)) || raise("expected match tuple")
        write_match payload_io, tup[0], tup[1]

      when OsuType::ScoreFrame
        sf = value.as?(ScoreFrame) || raise("expected scoreframe")
        write_scoreframe payload_io, sf

      else
        raise "unhandled OsuType: #{typ}"
      end
    end

    payload = payload_io.to_slice

    length = payload.size
    ret += Bytes[
      (length & 0xFF).to_u8,
      ((length >> 8) & 0xFF).to_u8,
      ((length >> 16) & 0xFF).to_u8,
      ((length >> 24) & 0xFF).to_u8
    ]

    ret += payload

    ret
  end

  def self.write_string(io : IO, str : String)
    io.write_byte 0x0B
    encode_uleb128(io, str.bytesize.to_u32)
    io.write str.to_slice
  end

  def self.encode_uleb128(io : IO, val : UInt32)
    loop do
      byte = val & 0x7F
      val >>= 7
      if val != 0
        io.write_byte (byte | 0x80).to_u8
      else
        io.write_byte byte.to_u8
        break
      end
    end
  end

  def self.write_i32_list(io : IO, list : Array(Int32))
    io.write_bytes list.size.to_u16, IO::ByteFormat::LittleEndian
    list.each { |n| io.write_bytes n, IO::ByteFormat::LittleEndian }
  end

  def self.write_message(io : IO, msg : Tuple(String, String, String, Int32))
    sender, text, target, sender_id = msg
    write_string(io, sender)
    write_string(io, text)
    write_string(io, target)
    io.write_bytes sender_id, IO::ByteFormat::LittleEndian
  end

  def self.write_channel(io : IO, channel : Tuple(String, String, Int32))
    name, topic, count = channel
    write_string(io, name)
    write_string(io, topic)
    io.write_bytes count.to_u16, IO::ByteFormat::LittleEndian
  end

  def self.write_match(io : IO, m : Match, send_pw : Bool = true)
    io.write_bytes m.id.to_i16, IO::ByteFormat::LittleEndian
    io.write_byte m.in_progress ? 1_u8 : 0_u8
    io.write_byte 0_u8  # match type (always standard)
    io.write_bytes m.mods.value, IO::ByteFormat::LittleEndian
    write_string(io, m.name)

    if m.passwd.empty?
      io.write_byte 0x00_u8
    elsif send_pw
      write_string(io, m.passwd)
    else
      io.write_bytes 0x0B_u8
      io.write_byte 0x00_u8
    end

    write_string(io, m.map_name)
    io.write_bytes m.map_id, IO::ByteFormat::LittleEndian
    write_string(io, m.map_md5)

    m.slots.each { |s| io.write_byte s.status.value }
    m.slots.each { |s| io.write_byte s.team.value }

    m.slots.each do |s|
      if s.status.has_player?
        io.write_bytes s.player.not_nil!.id, IO::ByteFormat::LittleEndian
      end
    end

    h = m.host
    io.write_bytes (h ? h.id : 0), IO::ByteFormat::LittleEndian
    io.write_byte m.mode.as_vn
    io.write_byte m.win_condition.value
    io.write_byte m.team_type.value
    io.write_byte m.freemods ? 1_u8 : 0_u8

    if m.freemods
      m.slots.each { |s| io.write_bytes s.mods.value, IO::ByteFormat::LittleEndian }
    end

    io.write_bytes m.seed, IO::ByteFormat::LittleEndian
  end

  def self.write_scoreframe(io : IO, sf : ScoreFrame)
    io.write_bytes sf.time, IO::ByteFormat::LittleEndian
    io.write_byte sf.id.to_u8
    io.write_bytes sf.num300, IO::ByteFormat::LittleEndian
    io.write_bytes sf.num100, IO::ByteFormat::LittleEndian
    io.write_bytes sf.num50, IO::ByteFormat::LittleEndian
    io.write_bytes sf.num_geki, IO::ByteFormat::LittleEndian
    io.write_bytes sf.num_katu, IO::ByteFormat::LittleEndian
    io.write_bytes sf.num_miss, IO::ByteFormat::LittleEndian
    io.write_bytes sf.total_score, IO::ByteFormat::LittleEndian
    io.write_bytes sf.max_combo, IO::ByteFormat::LittleEndian
    io.write_bytes sf.current_combo, IO::ByteFormat::LittleEndian
    io.write_byte sf.perfect ? 1_u8 : 0_u8
    io.write_byte sf.current_hp
    io.write_byte sf.tag_byte
    io.write_byte sf.score_v2 ? 1_u8 : 0_u8
    if sf.score_v2
      io.write_bytes sf.combo_portion.not_nil!, IO::ByteFormat::LittleEndian
      io.write_bytes sf.bonus_portion.not_nil!, IO::ByteFormat::LittleEndian
    end
  end
end
