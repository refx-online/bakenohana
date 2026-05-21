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

    params = HTTP::Params.build do |p|
      p.add "beatmap_id", beatmap_id.to_s
      p.add "mode", mode.as_vn.to_u32.to_s
      p.add "mods", mods.value.to_s
      p.add "max_combo", max_combo.to_s if max_combo
      p.add "accuracy", accuracy.to_s
      p.add "miss_count", miss_count.to_s if miss_count
      p.add "legacy_score", legacy_score.to_s if legacy_score
    end

    uri = URI.parse(Config.omajinai_url)
    response = HTTP::Client.get(
      "#{Config.omajinai_url}/calculate?#{params}",
      headers: HTTP::Headers{"Content-Type" => "application/json"}
    )

    raise "omajinai returned #{response.status_code}" unless response.status_code == 200

    parsed = ApiResponse.from_json(response.body)

    unless parsed.success
      raise "omajinai error: #{parsed.error}"
    end

    parsed.data.not_nil!
  end
end
