require "db"
require "../models/login_data"

struct UserHashRepo
  include DB::Serializable

  @[DB::Field(name: "userid")]
  property userid : Int32

  @[DB::Field(name: "osupath")]
  property osupath : String

  @[DB::Field(name: "adapters")]
  property adapters : String

  @[DB::Field(name: "uninstall_id")]
  property uninstall_id : String

  @[DB::Field(name: "disk_serial")]
  property disk_serial : String

  @[DB::Field(name: "occurrences")]
  property occurrences : Int32

  def self.create(user_id : Int32, login_data : LoginData, ip : String) : DB::ExecResult
    Services.db.execute(
      " insert into client_hashes (userid, osupath, adapters, uninstall_id, disk_serial, latest_time, occurrences)
        values (?, ?, ?, ?, ?, now(), 1)
        on duplicate key update latest_time = now(), occurrences = occurrences + 1 ",
      user_id,
      login_data.osu_path_md5,
      login_data.adapters_md5,
      login_data.uninstall_md5,
      login_data.disk_signature_md5
    )
  end

  def self.has_hw_conflict?(user_id : Int32, running_under_wine : Bool,
                             adapters : String, uninstall_id : String,
                             disk_serial : String) : Bool
    if running_under_wine
      result = Services.db.fetch_val(
        "select 1 from client_hashes where uninstall_id = ? and userid != ? limit 1",
        uninstall_id, user_id
      )
    else
      result = Services.db.fetch_val(
        "select 1 from client_hashes where userid != ? and (adapters = ? or uninstall_id = ? or disk_serial = ?) limit 1",
        user_id, adapters, uninstall_id, disk_serial
      )
    end
    !result.nil?
  end
end
