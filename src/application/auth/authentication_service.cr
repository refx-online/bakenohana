require "../../persistence/repositories/user"
require "../../persistence/repositories/user_hash"
require "../../persistence/models/login_data"

require "crypto/bcrypt"

module Auth
  def self.authenticate(username : String, untrusted_password : String) : UserRepo?
    user = UserRepo.fetch_one(username)
    return nil unless user

    parsed = Crypto::Bcrypt::Password.new(user.pw_bcrypt)

    verified = begin
      parsed.verify(untrusted_password)
    rescue
      false
    end

    return nil unless verified
    user
  end

  def self.validate_adapters(user_id : Int32, login_data : LoginData, ip : String) : Bool
    return false if login_data.username.empty? || login_data.password_md5.size != 32

    running_under_wine = login_data.disk_signature_md5 == "runningunderwine"

    conflict = UserHashRepo.has_hw_conflict?(
      user_id,
      running_under_wine,
      login_data.adapters_md5,
      login_data.uninstall_md5,
      login_data.disk_signature_md5
    )

    UserHashRepo.create(user_id, login_data, ip)
    !conflict
  end
end
