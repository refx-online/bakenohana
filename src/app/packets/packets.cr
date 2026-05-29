module Packets # thanks akatsuki
  enum ServerPacket : UInt16
    USER_ID = 5
    SEND_MESSAGE = 7
    PONG = 8
    USER_STATS = 11
    USER_PRESENCE = 83
    USER_LOGOUT = 12
    SPECTATOR_JOINED = 13
    SPECTATOR_LEFT = 14
    SPECTATE_FRAMES = 15
    VERSION_UPDATE = 19
    SPECTATOR_CANT_SPECTATE = 22
    NOTIFICATION = 24
    UPDATE_MATCH = 26
    NEW_MATCH = 27
    DISPOSE_MATCH = 28
    MATCH_JOIN_SUCCESS = 36
    MATCH_JOIN_FAIL = 37
    FELLOW_SPECTATOR_JOINED = 42
    FELLOW_SPECTATOR_LEFT = 43
    MATCH_START = 46
    MATCH_SCORE_UPDATE = 48
    MATCH_TRANSFER_HOST = 50
    MATCH_ALL_PLAYERS_LOADED = 53
    MATCH_PLAYER_FAILED = 57
    MATCH_COMPLETE = 58
    MATCH_SKIP = 61
    CHANNEL_JOIN = 64
    CHANNEL_INFO = 65
    CHANNEL_KICK = 66
    CHANNEL_AUTO_JOIN = 67
    PRIVILEGES = 71
    FRIENDS_LIST = 72
    MATCH_PLAYER_SKIPPED = 81
    RESTART = 86
    MATCH_INVITE = 88
    ACCOUNT_RESTRICTED = 104
    PROTOCOL_VERSION = 75
    CHANNEL_INFO_END = 89
    MATCH_CHANGE_PASSWORD = 91
    SILENCE_END = 92
    USER_SILENCED = 94
    USER_DM_BLOCKED = 100
    TARGET_IS_SILENCED = 101
    MATCH_ABORT = 106
  end

  alias TypeArg = Tuple

  enum OsuType
    I8; U8; I16; U16; I32; U32
    I64; U64; F32; F64
    String; I32List
    Message; Channel; Match; ScoreFrame
    Raw
  end

  # packet writers

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

  # now to write server packet

  def self.silence_end(delta : Int32) : Bytes
    write(ServerPacket::SILENCE_END, {delta, OsuType::I32})
  end

  def self.user_silenced(user_id : Int32) : Bytes
    write(ServerPacket::USER_SILENCED, {user_id, OsuType::I32})
  end

  def self.user_dm_blocked(target : String) : Bytes
    write(ServerPacket::USER_DM_BLOCKED, { {"", "", target, 0}, OsuType::Message })
  end

  def self.target_is_silenced(target : String) : Bytes
    write(ServerPacket::TARGET_IS_SILENCED, { {"", "", target, 0}, OsuType::Message })
  end

  def self.login_reply(user_id : Int32) : Bytes
    write(ServerPacket::USER_ID, {user_id, OsuType::I32})
  end

  def self.pong : Bytes
    write(ServerPacket::PONG, {Bytes.empty, OsuType::Raw})
  end

  def self.protocol_version(version : Int32) : Bytes
    write(ServerPacket::PROTOCOL_VERSION, {version, OsuType::I32})
  end

  def self.bancho_privileges(privs : Int32) : Bytes
    write(ServerPacket::PRIVILEGES, {privs, OsuType::I32})
  end

  def self.notification(msg : String) : Bytes
    write(ServerPacket::NOTIFICATION, {msg, OsuType::String})
  end

  def self.send_message(sender : String, msg : String, recipient : String, sender_id : Int32) : Bytes
    write(
      ServerPacket::SEND_MESSAGE,
      { {sender, msg, recipient, sender_id}, OsuType::Message }
    )
  end

  def self.logout(user_id : Int32) : Bytes
    write(ServerPacket::USER_LOGOUT, {user_id, OsuType::I32}, {0_u8, OsuType::U8})
  end

  def self.account_restricted : Bytes
    write(ServerPacket::ACCOUNT_RESTRICTED, {Bytes.empty, OsuType::Raw})
  end

  def self.channel_info_end : Bytes
    write(ServerPacket::CHANNEL_INFO_END, {Bytes.empty, OsuType::Raw})
  end

  def self.channel_info(name : String, topic : String, player_count : Int32) : Bytes
    write(
      ServerPacket::CHANNEL_INFO,
      { {name, topic, player_count}, OsuType::Channel }
    )
  end

  def self.channel_join(name : String) : Bytes
    write(
      ServerPacket::CHANNEL_JOIN, {name, OsuType::String}
    )
  end

  def self.channel_kick(name : String) : Bytes
    write(
      ServerPacket::CHANNEL_KICK, {name, OsuType::String}
    )
  end

  def self.user_stats(player : Player) : Bytes
    stats = player.stats
    pp = stats.pp
    rscore = stats.rscore

    # TODO: why? imagine if someone cheated their way to get this pp value
    if pp > 65535 || (player.refx && pp > Int32::MAX)
      rscore = pp.to_i64
      pp = 0
    end

    write(
      ServerPacket::USER_STATS,
      {player.id, OsuType::I32},
      {player.status.action, OsuType::U8},
      {player.status.info_text, OsuType::String},
      {player.status.map_md5, OsuType::String},
      {player.status.mods.to_u32, OsuType::U32},
      {player.status.mode.as_vn.to_u8, OsuType::U8},
      {player.status.map_id, OsuType::I32},
      {rscore, OsuType::I64},
      {(stats.acc.to_f32 / 100.0_f32), OsuType::F32},
      {stats.plays, OsuType::I32},
      {stats.tscore, OsuType::I64},
      {stats.global_rank, OsuType::I32},
      {pp.to_u16, OsuType::U16}
    )
  end

  def self.bot_stats(player : Player) : Bytes
    write(
      ServerPacket::USER_STATS,
      {1, OsuType::I32},
      {6_u8, OsuType::U8},
      {"you", OsuType::String},
      {"", OsuType::String},
      {0_u32, OsuType::U32},
      {0_u8, OsuType::U8},
      {0, OsuType::I32},
      {0_i64, OsuType::I64},
      {(67_f32 / 100.0_f32), OsuType::F32},
      {67, OsuType::I32},
      {0_i64, OsuType::I64},
      {0, OsuType::I32},
      {67_u16, OsuType::U16}
    )
  end

  def self.user_presence(player : Player) : Bytes
    write(
      ServerPacket::USER_PRESENCE,
      {player.id, OsuType::I32},
      {player.username, OsuType::String},
      {(player.status.utc_offset + 24).to_u8, OsuType::U8},
      {player.status.country_code.to_u8, OsuType::U8},
      {(player.client_priv.value | (player.status.mode.as_vn << 5)).to_u8, OsuType::U8},
      {player.status.longitude, OsuType::F32},
      {player.status.latitude, OsuType::F32},
      {player.stats.global_rank, OsuType::I32}
    )
  end

  def self.bot_presence(player : Player) : Bytes
    write(
      ServerPacket::USER_PRESENCE,
      {1, OsuType::I32},
      {player.username, OsuType::String},
      {(-24 + 24).to_u8, OsuType::U8},
      {1_u8, OsuType::U8},
      {(player.client_priv.value | (player.status.mode.as_vn << 5)).to_u8, OsuType::U8},
      {1_f32, OsuType::F32},
      {1_f32, OsuType::F32},
      {0, OsuType::I32}
    )
  end

  def self.friends_list(friends : Enumerable(Int32)) : Bytes
    write(ServerPacket::FRIENDS_LIST, {friends.to_a, OsuType::I32List})
  end

  def self.restart_server(ms : Int32) : Bytes
    write(ServerPacket::RESTART, {ms, OsuType::I32})
  end

  def self.spectator_joined(user_id : Int32) : Bytes
    write(ServerPacket::SPECTATOR_JOINED, {user_id, OsuType::I32})
  end

  def self.spectator_left(user_id : Int32) : Bytes
    write(ServerPacket::SPECTATOR_LEFT, {user_id, OsuType::I32})
  end

  def self.spectator_frames(frame : Bytes) : Bytes
    write(ServerPacket::SPECTATE_FRAMES, {frame, OsuType::Raw})
  end

  def self.spectator_cant_spectate(user_id : Int32) : Bytes
    write(ServerPacket::SPECTATOR_CANT_SPECTATE, {user_id, OsuType::I32})
  end

  def self.f_spectator_joined(user_id : Int32) : Bytes
    write(ServerPacket::FELLOW_SPECTATOR_JOINED, {user_id, OsuType::I32})
  end

  def self.f_spectator_left(user_id : Int32) : Bytes
    write(ServerPacket::FELLOW_SPECTATOR_LEFT, {user_id, OsuType::I32})
  end

  def self.update_match(m : Match, send_pw : Bool = true) : Bytes
    write(ServerPacket::UPDATE_MATCH, { {m, send_pw}, OsuType::Match })
  end

  def self.new_match(m : Match) : Bytes
    write(ServerPacket::NEW_MATCH, { {m, true}, OsuType::Match })
  end

  def self.dispose_match(id : Int32) : Bytes
    write(ServerPacket::DISPOSE_MATCH, {id, OsuType::I32})
  end

  def self.match_join_success(m : Match) : Bytes
    write(ServerPacket::MATCH_JOIN_SUCCESS, { {m, true}, OsuType::Match })
  end

  def self.match_join_fail : Bytes
    write(ServerPacket::MATCH_JOIN_FAIL, {Bytes.empty, OsuType::Raw})
  end

  def self.match_start(m : Match) : Bytes
    write(ServerPacket::MATCH_START, { {m, true}, OsuType::Match })
  end

  def self.match_score_update(sf : ScoreFrame) : Bytes
    write(ServerPacket::MATCH_SCORE_UPDATE, {sf, OsuType::ScoreFrame})
  end

  def self.match_transfer_host : Bytes
    write(ServerPacket::MATCH_TRANSFER_HOST, {Bytes.empty, OsuType::Raw})
  end

  def self.match_all_players_loaded : Bytes
    write(ServerPacket::MATCH_ALL_PLAYERS_LOADED, {Bytes.empty, OsuType::Raw})
  end

  def self.match_player_failed(slot_id : Int32) : Bytes
    write(ServerPacket::MATCH_PLAYER_FAILED, {slot_id, OsuType::I32})
  end

  def self.match_complete : Bytes
    write(ServerPacket::MATCH_COMPLETE, {Bytes.empty, OsuType::Raw})
  end

  def self.match_skip : Bytes
    write(ServerPacket::MATCH_SKIP, {Bytes.empty, OsuType::Raw})
  end

  def self.match_player_skipped(user_id : Int32) : Bytes
    write(ServerPacket::MATCH_PLAYER_SKIPPED, {user_id, OsuType::I32})
  end

  def self.match_invite(sender_name : String, sender_id : Int32, target_name : String, match_embed : String) : Bytes
    msg = "Come join my game: #{match_embed}."
    write(
      ServerPacket::MATCH_INVITE,
      { {sender_name, msg, target_name, sender_id}, OsuType::Message }
    )
  end

  def self.match_change_password(passwd : String) : Bytes
    write(ServerPacket::MATCH_CHANGE_PASSWORD, {passwd, OsuType::String})
  end

  def self.match_abort : Bytes
    write(ServerPacket::MATCH_ABORT, {Bytes.empty, OsuType::Raw})
  end
end