require "json"
require "../../../state/player_session"
require "../../../persistence/repositories/user"

module Api::V1
  def self.register_get_player_count
    get "/api/v1/get_player_count" do |env|
      env.response.content_type = "application/json"
      online = PlayerSession.unrestricted_count - 1
      total  = UserRepo.fetch_count
      {"status" => "success", "counts" => {"online" => online, "total" => total}}.to_json
    end
  end
end
