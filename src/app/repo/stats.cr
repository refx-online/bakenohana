require "db"

struct StatsRepo
  include DB::Serializable

  @[DB::Field(name: "id")]
  property id : Int32

  @[DB::Field(name: "mode")]
  property mode : Int8

  @[DB::Field(name: "tscore")]
  property tscore : UInt64

  @[DB::Field(name: "rscore")]
  property rscore : UInt64

  @[DB::Field(name: "pp")]
  property pp : UInt32

  @[DB::Field(name: "plays")]
  property plays : UInt32

  @[DB::Field(name: "playtime")]
  property playtime : UInt32

  @[DB::Field(name: "acc")]
  property acc : Float32

  @[DB::Field(name: "max_combo")]
  property max_combo : UInt32

  @[DB::Field(name: "total_hits")]
  property total_hits : UInt32

  @[DB::Field(name: "replay_views")]
  property replay_views : UInt32

  @[DB::Field(name: "xh_count")]
  property xh_count : UInt32

  @[DB::Field(name: "x_count")]
  property x_count : UInt32

  @[DB::Field(name: "sh_count")]
  property sh_count : UInt32

  @[DB::Field(name: "s_count")]
  property s_count : UInt32

  @[DB::Field(name: "a_count")]
  property a_count : UInt32

  def self.fetch_one(user_id : Int32, mode : Int32) : self?
    Services.db.fetch_one(self, "select * from stats where id = ? and mode = ?", user_id, mode.to_i8)
  end

  def self.fetch_all_for(user_id : Int32) : Array(self)
    Services.db.fetch_all(self, "select * from stats where id = ?", user_id)
  end
end
