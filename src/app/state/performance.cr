require "http/client"
require "json"
require "../config"
require "../consts/mods"
require "../consts/mode"

class OsuPerformanceCalculator
  struct PerformanceResult
    include JSON::Serializable

    getter pp : Float64
    getter hypothetical_pp : Float64
    getter stars : Float64
    getter max_combo : UInt32
  end

  private struct ApiResponse
    include JSON::Serializable

    getter success : Bool
    getter data : PerformanceResult?
    getter error : String?
  end

  def self.calculate_score(
    beatmap_id : Int32,
    mode : Gamemode = Gamemode::VN_OSU,
    mods : Mods = Mods::NOMOD,
    max_combo : UInt32? = nil,
    accuracy : Float64 = 100.0,
    miss_count : UInt32? = nil,
    legacy_score : Int64? = nil,
  ) : PerformanceResult
    raise "accuracy must be between 0 and 100" unless (0.0..100.0).includes?(accuracy)

    if mode.value >= Gamemode::CHEAT_OSU.value && mode.value <= Gamemode::CHEAT_CHEAT_MANIA.value
      mods |= Mods::RELAX
    end

    body = JSON.build do |j|
      j.object do
        j.field "beatmap_id", beatmap_id
        j.field "mode", mode.as_vn.to_u32
        j.field "mods", mods.value unless mods.value == 0
        j.field "max_combo", max_combo if max_combo
        j.field "accuracy", accuracy
        j.field "miss_count", miss_count if miss_count
        j.field "legacy_score", legacy_score if legacy_score
      end
    end

    uri = URI.parse(Config.omajinai_url)
    response = HTTP::Client.post(
      "#{Config.omajinai_url}/calculate",
      headers: HTTP::Headers{"Content-Type" => "application/json"},
      body: body
    )

    raise "omajinai returned #{response.status_code}" unless response.status_code == 200

    parsed = ApiResponse.from_json(response.body)

    unless parsed.success
      raise "omajinai error: #{parsed.error}"
    end

    parsed.data.not_nil!
  end
end
