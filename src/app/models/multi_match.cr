# Wire-format match data read from client packets
struct MultiMatch
  property id : Int16
  property in_progress : Bool
  property powerplay : Int8
  property mods : Int32
  property name : String
  property passwd : String
  property map_name : String
  property map_id : Int32
  property map_md5 : String
  property slot_statuses : Array(Int8)
  property slot_teams : Array(Int8)
  property slot_ids : Array(Int32)
  property host_id : Int32
  property mode : Int8
  property win_condition : Int8
  property team_type : Int8
  property freemods : Bool
  property slot_mods : Array(Int32)
  property seed : Int32

  def initialize
    @id = 0_i16
    @in_progress = false
    @powerplay = 0_i8
    @mods = 0
    @name = ""
    @passwd = ""
    @map_name = ""
    @map_id = 0
    @map_md5 = ""
    @slot_statuses = Array(Int8).new(16, 0_i8)
    @slot_teams = Array(Int8).new(16, 0_i8)
    @slot_ids = Array(Int32).new
    @host_id = 0
    @mode = 0_i8
    @win_condition = 0_i8
    @team_type = 0_i8
    @freemods = false
    @slot_mods = Array(Int32).new(16, 0)
    @seed = 0
  end
end
