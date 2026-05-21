require "json"
require "../../state/sessions"
require "../../repo/user"

module Api::V1
  def self.register_get_player_status
    get "/api/v1/get_player_status" do |env|
      env.response.content_type = "application/json"

      id_param   = env.params.query["id"]?
      name_param = env.params.query["name"]?

      if (id_param && name_param) || (!id_param && !name_param)
        env.response.status_code = 400
        next({"status" => "Must provide either id OR name!"}.to_json)
      end

      player = if name_param
        PlayerSession.get(username: name_param)
      else
        PlayerSession.get(id: id_param.not_nil!.to_i)
      end

      if player.nil?
        row = if name_param
          UserRepo.fetch_one(name_param.not_nil!)
        else
          UserRepo.fetch_one(id_param.not_nil!.to_i)
        end

        if row.nil?
          env.response.status_code = 404
          next({"status" => "Player not found."}.to_json)
        end

        next({
          "status" => "success",
          "player_status" => {
            "online"    => false,
            "last_seen" => row.latest_activity,
          },
        }.to_json)
      end

      {
        "status" => "success",
        "player_status" => {
          "online"     => true,
          "login_time" => player.login_time.to_unix,
          "status" => {
            "action"    => player.status.action,
            "info_text" => player.status.info_text,
            "mode"      => player.status.mode.value,
            "mods"      => player.status.mods.value,
            "map_md5"   => player.status.map_md5,
            "map_id"    => player.status.map_id,
          },
        },
      }.to_json
    end
  end
end
