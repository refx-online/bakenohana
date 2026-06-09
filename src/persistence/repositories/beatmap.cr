require "db"
require "../../persistence/database"

enum RankedStatus
  Inactive        = -3
  NotSubmitted    = -1
  Pending         =  0
  UpdateAvailable =  1
  Ranked          =  2
  Approved        =  3
  Qualified       =  4
  Loved           =  5

  def to_s : String
    case self
    when Ranked          then "ranked"
    when Approved        then "approved"
    when Qualified       then "qualified"
    when Loved           then "loved"
    when Pending         then "unranked"
    when UpdateAvailable then "outdated"
    when NotSubmitted    then "unsubmitted"
    else                      "inactive"
    end
  end
end

struct BeatmapRepo
  include DB::Serializable

  @[DB::Field(name: "id")]
  property id : Int32

  @[DB::Field(name: "set_id")]
  property set_id : Int32

  @[DB::Field(name: "status")]
  property status : Int32

  @[DB::Field(name: "md5")]
  property md5 : String

  @[DB::Field(name: "artist")]
  property artist : String

  @[DB::Field(name: "title")]
  property title : String

  @[DB::Field(name: "version")]
  property version : String

  @[DB::Field(name: "creator")]
  property creator : String

  @[DB::Field(name: "total_length")]
  property total_length : Int32 = 0

  @[DB::Field(name: "diff")]
  property diff : Float32 = 0_f32

  @[DB::Field(name: "cs")]
  property cs : Float32 = 0_f32

  @[DB::Field(name: "od")]
  property od : Float32 = 0_f32

  @[DB::Field(name: "ar")]
  property ar : Float32 = 0_f32

  @[DB::Field(name: "hp")]
  property hp : Float32 = 0_f32

  def ranked_status : RankedStatus
    RankedStatus.new(@status)
  end

  def embed : String
    "[https://osu.ppy.sh/b/#{@id} #{@artist} - #{@title} [#{@version}]]"
  end

  def self.fetch_one(map_id : Int32) : self?
    Services.db.fetch_one(self,
      "select id, set_id, status, md5, artist, title, version, creator, total_length, diff, cs, od, ar, hp from maps where id = ?",
      map_id)
  end

  def self.update_status(map_id : Int32, status : RankedStatus) : DB::ExecResult
    Services.db.execute(
      "update maps set status = ?, frozen = 1 where id = ?",
      status.value, map_id)
  end

  def self.update_set_status(set_id : Int32, status : RankedStatus) : DB::ExecResult
    Services.db.execute(
      "update maps set status = ?, frozen = 1 where set_id = ?",
      status.value, set_id)
  end
end
