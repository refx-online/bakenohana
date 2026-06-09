require "./v1/get_player_count"
require "./v1/get_player_status"
require "./v1/get_online"

module Api::V1
  def self.register_routes
    register_get_player_count
    register_get_player_status
    register_get_online
  end
end
