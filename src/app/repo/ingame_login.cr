require "db"

struct IngameLoginRepo
  include DB::Serializable

  @[DB::Field]
  property id : Int32

  @[DB::Field]
  property userid : Int32

  @[DB::Field]
  property ip : String

  @[DB::Field]
  property osu_ver : String

  @[DB::Field]
  property osu_stream : String

  def self.create(user_id : Int32, ip : String, osu_ver : String, osu_stream : String) : DB::ExecResult
    Services.db.execute(
      "insert into ingame_logins (userid, ip, osu_ver, osu_stream, datetime) values (?, ?, ?, ?, now())",
      user_id, ip, osu_ver, osu_stream
    )
  end
end
