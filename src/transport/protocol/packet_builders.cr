require "./packet_types"
require "./packet_writer"
require "../../domain/player/player"
require "../../domain/match/match"
require "../../shared/value_objects/score_frame"

module Packets
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
