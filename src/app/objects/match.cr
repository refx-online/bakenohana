require "../consts/mods"
require "../consts/mode"
require "../consts/priv"
require "../log"

@[Flags]
enum SlotStatus : UInt8
  Open     = 1
  Locked   = 2
  NotReady = 4
  Ready    = 8
  NoMap    = 16
  Playing  = 32
  Complete = 64
  Quit     = 128

  def has_player? : Bool
    (value & 0b01111100) != 0
  end
end

enum MatchTeams : UInt8
  Neutral = 0
  Blue    = 1
  Red     = 2
end

enum MatchWinConditions : UInt8
  Score    = 0
  Accuracy = 1
  Combo    = 2
  ScoreV2  = 3
end

enum MatchTeamTypes : UInt8
  HeadToHead  = 0
  TagCoop     = 1
  TeamVs      = 2
  TagTeamVs   = 3
end

class Slot
  property player : Player?
  property status : SlotStatus
  property team : MatchTeams
  property mods : Mods
  property loaded : Bool
  property skipped : Bool

  def initialize
    @player = nil
    @status = SlotStatus::Open
    @team = MatchTeams::Neutral
    @mods = Mods::NOMOD
    @loaded = false
    @skipped = false
  end

  def empty? : Bool
    @player.nil?
  end

  def copy_from(other : Slot) : Nil
    @player = other.player
    @status = other.status
    @team = other.team
    @mods = other.mods
  end

  def reset(new_status : SlotStatus = SlotStatus::Open) : Nil
    @player = nil
    @status = new_status
    @team = MatchTeams::Neutral
    @mods = Mods::NOMOD
    @loaded = false
    @skipped = false
  end
end

MAX_MATCH_NAME_LEN = 50

class Match
  getter id : Int32
  property name : String
  property passwd : String
  property host_id : Int32
  property map_id : Int32
  property map_md5 : String
  property map_name : String
  property prev_map_id : Int32
  property mods : Mods
  property mode : Gamemode
  property freemods : Bool
  property chat : Channels
  property slots : Array(Slot)
  property team_type : MatchTeamTypes
  property win_condition : MatchWinConditions
  property in_progress : Bool
  property seed : Int32

  def initialize(
    @id : Int32,
    @name : String,
    @passwd : String,
    @host_id : Int32,
    @map_id : Int32,
    @map_md5 : String,
    @map_name : String,
    @mods : Mods,
    @mode : Gamemode,
    @win_condition : MatchWinConditions,
    @team_type : MatchTeamTypes,
    @freemods : Bool,
    @seed : Int32,
    @chat : Channels
  )
    @prev_map_id = 0
    @in_progress = false
    @slots = Array(Slot).new(16) { Slot.new }
  end

  def url : String
    "osump://#{@id}/#{@passwd}"
  end

  def embed : String
    "[#{url} #{@name}]"
  end

  def get_slot(player : Player) : Slot?
    @slots.find { |s| s.player.same?(player) }
  end

  def get_slot_id(player : Player) : Int32?
    @slots.each_with_index do |s, i|
      return i if s.player.same?(player)
    end
    nil
  end

  def get_free : Int32?
    @slots.each_with_index do |s, i|
      return i if s.status == SlotStatus::Open
    end
    nil
  end

  def get_host_slot : Slot?
    h = host
    return nil unless h
    @slots.find { |s| s.player.same?(h) }
  end

  def copy(m : Match) : Nil
    @map_id = m.map_id
    @map_md5 = m.map_md5
    @map_name = m.map_name
    @freemods = m.freemods
    @mode = m.mode
    @team_type = m.team_type
    @win_condition = m.win_condition
    @mods = m.mods
    @name = m.name
  end

  def enqueue(data : Bytes, lobby : Bool = true, immune : Array(Int32) = [] of Int32) : Nil
    @chat.enqueue(data, immune)

    if lobby
      lchan = ChannelSession.get_by_name("#lobby")
      lchan.try(&.enqueue(data))
    end
  end

  def enqueue_state(lobby : Bool = true) : Nil
    @chat.enqueue(Packets.update_match(self, send_pw: true))

    if lobby
      lchan = ChannelSession.get_by_name("#lobby")
      if lchan && lchan.player_count > 0
        lchan.enqueue(Packets.update_match(self, send_pw: false))
      end
    end
  end

  def unready_players(expected : SlotStatus = SlotStatus::Ready) : Nil
    @slots.each do |s|
      s.status = SlotStatus::NotReady if s.status == expected
    end
  end

  def reset_players_loaded_status : Nil
    @slots.each do |s|
      s.loaded = false
      s.skipped = false
    end
  end

  def start : Nil
    no_map = [] of Int32

    @slots.each do |s|
      if s.player
        if s.status != SlotStatus::NoMap
          s.status = SlotStatus::Playing
        else
          no_map << s.player.not_nil!.id
        end
      end
    end

    @in_progress = true
    enqueue(Packets.match_start(self), lobby: false, immune: no_map)
    enqueue_state
  end
end
