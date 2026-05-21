require "./v1/get_player_count"
require "./v1/get_player_status"

module Api::V1
  def self.register_routes
    register_get_player_count
    register_get_player_status
  end
end
