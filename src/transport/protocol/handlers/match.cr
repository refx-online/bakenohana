require "../../../domain/match/match"
require "../../../state/match_session"
require "../../../state/player_session"
require "../../../infrastructure/logging/logger"

abstract class MatchHandlerBase < BasePacket
  def handle(p : Player)
    m = p.match
    return unless m
    handle_match(p, m)
  end

  abstract def handle_match(p : Player, m : Match)
end

class JoinLobbyPacket < BasePacket
  def handle(p : Player)
    p.in_lobby = true

    MatchSession.each do |m|
      p.enqueue(Packets.new_match(m))
    end
  end
end

class PartLobbyPacket < BasePacket
  def handle(p : Player)
    p.in_lobby = false
  end
end

class CreateMatchPacket < BasePacket
  def initialize(@reader : BanchoPacketReader)
    @data = @reader.read_match
  end

  def handle(p : Player)
    if p.restricted
      p.enqueue(
        Packets.match_join_fail +
        Packets.notification("Multiplayer is not available while restricted.")
      )
      return
    end

    if p.silenced?
      p.enqueue(
        Packets.match_join_fail +
        Packets.notification("Multiplayer is not available while silenced.")
      )
      return
    end

    if @data.host_id != p.id || @data.name.size > MAX_MATCH_NAME_LEN
      rlog "#{p.username} sent invalid create match data.", Ansi::LYELLOW
      p.enqueue(Packets.match_join_fail)
      return
    end

    match_id = MatchSession.get_free
    if match_id.nil?
      p.send_msg("Failed to create match (no slots available).", PlayerSession.bot)
      p.enqueue(Packets.match_join_fail)
      return
    end

    chat = Channels.new(
      name: "#multi_#{match_id}",
      topic: "MID #{match_id}'s multiplayer channel.",
      auto_join: false,
      instance: true
    )

    match = Match.new(
      id: match_id,
      name: @data.name,
      passwd: @data.passwd,
      host_id: @data.host_id,
      map_id: @data.map_id,
      map_md5: @data.map_md5,
      map_name: @data.map_name,
      mods: Mods.new(@data.mods.to_u32),
      mode: Gamemode.new(@data.mode.to_u8),
      win_condition: MatchWinConditions.new(@data.win_condition.to_u8),
      team_type: MatchTeamTypes.new(@data.team_type.to_u8),
      freemods: @data.freemods,
      seed: @data.seed,
      chat: chat
    )

    MatchSession[match_id] = match
    ChannelSession.append(chat)

    p.join_match(match, @data.passwd)

    match.chat.send_msg("Match created by #{p.username}.", PlayerSession.bot)
    rlog "#{p.username} created match #{match.name} (#{match_id})", Ansi::LCYAN
  end
end

class JoinMatchPacket < BasePacket
  def initialize(@reader : BanchoPacketReader)
    @match_id = @reader.read_i32
    @passwd   = @reader.read_string
  end

  def handle(p : Player)
    match = MatchSession[@match_id]
    unless match
      rlog "#{p.username} tried to join non-existent match #{@match_id}.", Ansi::LYELLOW
      p.enqueue(Packets.match_join_fail)
      return
    end

    if p.restricted
      p.enqueue(
        Packets.match_join_fail +
        Packets.notification("Multiplayer is not available while restricted.")
      )
      return
    end

    if p.silenced?
      p.enqueue(
        Packets.match_join_fail +
        Packets.notification("Multiplayer is not available while silenced.")
      )
      return
    end

    p.join_match(match, @passwd)
  end
end

class PartMatchPacket < BasePacket
  def handle(p : Player)
    p.leave_match
  end
end

# ── In-match actions ───────────────────────────────────────────────────────

class MatchChangeSlotPacket < MatchHandlerBase
  def initialize(@reader : BanchoPacketReader)
    @slot_id = @reader.read_i32
  end

  def handle_match(p : Player, m : Match)
    return unless 0 <= @slot_id < 16

    if m.slots[@slot_id].status != SlotStatus::Open
      rlog "#{p.username} tried to move into non-open slot.", Ansi::LYELLOW
      return
    end

    slot = m.get_slot(p)
    return unless slot

    m.slots[@slot_id].copy_from(slot)
    slot.reset

    m.enqueue_state
  end
end

class MatchReadyPacket < MatchHandlerBase
  def handle_match(p : Player, m : Match)
    slot = m.get_slot(p)
    return unless slot

    slot.status = SlotStatus::Ready
    m.enqueue_state
  end
end

class MatchNotReadyPacket < MatchHandlerBase
  def handle_match(p : Player, m : Match)
    slot = m.get_slot(p)
    return unless slot

    slot.status = SlotStatus::NotReady
    m.enqueue_state
  end
end

class MatchLockPacket < MatchHandlerBase
  def initialize(@reader : BanchoPacketReader)
    @slot_id = @reader.read_i32
  end

  def handle_match(p : Player, m : Match)
    return unless p.same?(m.host)
    return unless 0 <= @slot_id < 16

    slot = m.slots[@slot_id]

    if slot.status == SlotStatus::Locked
      slot.status = SlotStatus::Open
    else
      return if slot.player.same?(m.host)
      slot.status = SlotStatus::Locked
    end

    m.enqueue_state
  end
end

class MatchChangeSettingsPacket < MatchHandlerBase
  def initialize(@reader : BanchoPacketReader)
    @data = @reader.read_match
  end

  def handle_match(p : Player, m : Match)
    return unless p.same?(m.host)

    if @data.host_id != p.id || @data.name.size > MAX_MATCH_NAME_LEN
      rlog "#{p.username} sent invalid change settings data.", Ansi::LYELLOW
      return
    end

    if @data.freemods != m.freemods
      m.freemods = @data.freemods

      if @data.freemods
        m.slots.each do |s|
          if s.player
            s.mods = Mods.new(m.mods.value & ~Mods::SPEED_CHANGING.value)
          end
        end
        m.mods = Mods.new(m.mods.value & Mods::SPEED_CHANGING.value)
      else
        host_slot = m.get_host_slot
        if host_slot
          m.mods = Mods.new((m.mods.value & Mods::SPEED_CHANGING.value) | host_slot.mods.value)
        end
        m.slots.each { |s| s.mods = Mods::NOMOD if s.player }
      end
    end

    if @data.map_id == -1
      m.unready_players(expected: SlotStatus::Ready)
      m.prev_map_id = m.map_id
      m.map_id   = -1
      m.map_md5  = ""
      m.map_name = ""
    elsif m.map_id == -1
      if m.prev_map_id != @data.map_id
        map_url   = "https://osu.#{Config.domain}/b/#{@data.map_id}"
        map_embed = "[#{map_url} #{@data.map_name}]"
        m.chat.send_msg("Selected: #{map_embed}.", PlayerSession.bot)
      end

      m.map_id   = @data.map_id
      m.map_md5  = @data.map_md5
      m.map_name = @data.map_name
      m.mode     = Gamemode.new(@data.mode.to_u8)
    end

    if m.team_type != MatchTeamTypes.new(@data.team_type.to_u8)
      new_team_type = MatchTeamTypes.new(@data.team_type.to_u8)
      new_t = (new_team_type == MatchTeamTypes::HeadToHead || new_team_type == MatchTeamTypes::TagCoop) ?
        MatchTeams::Neutral : MatchTeams::Red

      m.slots.each { |s| s.team = new_t if s.player }
      m.team_type = new_team_type
    end

    m.win_condition = MatchWinConditions.new(@data.win_condition.to_u8)
    m.name = @data.name

    m.enqueue_state
  end
end

class MatchStartPacket < MatchHandlerBase
  def handle_match(p : Player, m : Match)
    return unless p.same?(m.host)

    m.start
    m.enqueue_state
  end
end

class MatchScoreUpdatePacket < MatchHandlerBase
  def initialize(@reader : BanchoPacketReader)
    @frame = @reader.read_scoreframe
  end

  def handle_match(p : Player, m : Match)
    slot_id = m.get_slot_id(p)
    return unless slot_id

    @frame.id = slot_id
    m.enqueue(Packets.match_score_update(@frame), lobby: false)
  end
end

class MatchCompletePacket < MatchHandlerBase
  def handle_match(p : Player, m : Match)
    slot = m.get_slot(p)
    return unless slot

    slot.status = SlotStatus::Complete

    return if m.slots.any? { |s| s.status == SlotStatus::Playing }

    not_playing = m.slots
      .select { |s| s.player && s.status != SlotStatus::Complete }
      .map { |s| s.player.not_nil!.id }

    m.unready_players(expected: SlotStatus::Complete)
    m.reset_players_loaded_status
    m.in_progress = false

    m.enqueue(Packets.match_complete, lobby: false, immune: not_playing)
    m.enqueue_state
  end
end

class MatchChangeModsPacket < MatchHandlerBase
  def initialize(@reader : BanchoPacketReader)
    @mods = @reader.read_i32
  end

  def handle_match(p : Player, m : Match)

    if m.freemods
      if p.same?(m.host)
        m.mods = Mods.new(@mods.to_u32 & Mods::SPEED_CHANGING.value)
      end
      slot = m.get_slot(p)
      return unless slot
      slot.mods = Mods.new(@mods.to_u32 & ~Mods::SPEED_CHANGING.value)
    else
      return unless p.same?(m.host)
      m.mods = Mods.new(@mods.to_u32)
    end

    m.enqueue_state
  end
end

class MatchLoadCompletePacket < MatchHandlerBase
  def handle_match(p : Player, m : Match)
    slot = m.get_slot(p)
    return unless slot

    slot.loaded = true

    all_loaded = !m.slots.any? { |s| s.status == SlotStatus::Playing && !s.loaded }
    m.enqueue(Packets.match_all_players_loaded, lobby: false) if all_loaded
  end
end

class MatchNoBeatmapPacket < MatchHandlerBase
  def handle_match(p : Player, m : Match)
    slot = m.get_slot(p)
    return unless slot

    slot.status = SlotStatus::NoMap
    m.enqueue_state(lobby: false)
  end
end

class MatchHasBeatmapPacket < MatchHandlerBase
  def handle_match(p : Player, m : Match)
    slot = m.get_slot(p)
    return unless slot

    slot.status = SlotStatus::NotReady
    m.enqueue_state(lobby: false)
  end
end

class MatchFailedPacket < MatchHandlerBase
  def handle_match(p : Player, m : Match)
    slot_id = m.get_slot_id(p)
    return unless slot_id

    m.enqueue(Packets.match_player_failed(slot_id), lobby: false)
  end
end

class MatchSkipRequestPacket < MatchHandlerBase
  def handle_match(p : Player, m : Match)
    slot = m.get_slot(p)
    return unless slot

    slot.skipped = true
    m.enqueue(Packets.match_player_skipped(p.id))

    all_skipped = !m.slots.any? { |s| s.status == SlotStatus::Playing && !s.skipped }
    m.enqueue(Packets.match_skip, lobby: false) if all_skipped
  end
end

class MatchTransferHostPacket < MatchHandlerBase
  def initialize(@reader : BanchoPacketReader)
    @slot_id = @reader.read_i32
  end

  def handle_match(p : Player, m : Match)
    return unless p.same?(m.host)
    return unless 0 <= @slot_id < 16

    target = m.slots[@slot_id].player
    unless target
      rlog "#{p.username} tried to transfer host to empty slot.", Ansi::LYELLOW
      return
    end

    m.host_id = target.id
    m.host.try(&.enqueue(Packets.match_transfer_host))
    m.enqueue_state
  end
end

class MatchInvitePacket < MatchHandlerBase
  def initialize(@reader : BanchoPacketReader)
    @user_id = @reader.read_i32
  end

  def handle_match(p : Player, m : Match)
    target = PlayerSession.get(id: @user_id)
    unless target
      rlog "#{p.username} tried to invite offline user #{@user_id}.", Ansi::LYELLOW
      return
    end

    if target.id == PlayerSession.bot.id
      p.send_msg("I'm too busy!", PlayerSession.bot)
      return
    end

    target.enqueue(Packets.match_invite(p.username, p.id, target.username, m.embed))
    rlog "#{p.username} invited #{target.username} to #{m.name}.", Ansi::LCYAN
  end
end

class MatchChangePasswordPacket < MatchHandlerBase
  def initialize(@reader : BanchoPacketReader)
    @data = @reader.read_match
  end

  def handle_match(p : Player, m : Match)
    return unless p.same?(m.host)

    if @data.host_id != p.id
      rlog "#{p.username} sent invalid change password data.", Ansi::LYELLOW
      return
    end

    m.passwd = @data.passwd
    m.enqueue_state
  end
end

class MatchChangeTeamPacket < MatchHandlerBase
  def handle_match(p : Player, m : Match)
    slot = m.get_slot(p)
    return unless slot

    slot.team = slot.team == MatchTeams::Blue ? MatchTeams::Red : MatchTeams::Blue
    m.enqueue_state(lobby: false)
  end
end

register ClientPackets::JOIN_LOBBY,            JoinLobbyPacket
register ClientPackets::PART_LOBBY,            PartLobbyPacket
register ClientPackets::CREATE_MATCH,          CreateMatchPacket
register ClientPackets::JOIN_MATCH,            JoinMatchPacket
register ClientPackets::PART_MATCH,            PartMatchPacket
register ClientPackets::MATCH_CHANGE_SLOT,     MatchChangeSlotPacket
register ClientPackets::MATCH_READY,           MatchReadyPacket
register ClientPackets::MATCH_NOT_READY,       MatchNotReadyPacket
register ClientPackets::MATCH_LOCK,            MatchLockPacket
register ClientPackets::MATCH_CHANGE_SETTINGS, MatchChangeSettingsPacket
register ClientPackets::MATCH_START,           MatchStartPacket
register ClientPackets::MATCH_SCORE_UPDATE,    MatchScoreUpdatePacket
register ClientPackets::MATCH_COMPLETE,        MatchCompletePacket
register ClientPackets::MATCH_CHANGE_MODS,     MatchChangeModsPacket
register ClientPackets::MATCH_LOAD_COMPLETE,   MatchLoadCompletePacket
register ClientPackets::MATCH_NO_BEATMAP,      MatchNoBeatmapPacket
register ClientPackets::MATCH_HAS_BEATMAP,     MatchHasBeatmapPacket
register ClientPackets::MATCH_FAILED,          MatchFailedPacket
register ClientPackets::MATCH_SKIP_REQUEST,    MatchSkipRequestPacket
register ClientPackets::MATCH_TRANSFER_HOST,   MatchTransferHostPacket
register ClientPackets::MATCH_INVITE,          MatchInvitePacket
register ClientPackets::MATCH_CHANGE_PASSWORD, MatchChangePasswordPacket
register ClientPackets::MATCH_CHANGE_TEAM,     MatchChangeTeamPacket
