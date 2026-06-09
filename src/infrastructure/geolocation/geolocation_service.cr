require "http/client"
require "../../shared/helpers/country_codes"
require "../logging/logger"

module Geoloc
  record Result,
    country : String,
    country_code : Int32,
    latitude : Float32,
    longitude : Float32

  def self.fetch(ip : String, headers : HTTP::Headers) : Result
    if cf = headers["CF-IPCountry"]?
      code = cf.downcase
      if numeric = COUNTRY_CODES[code]?
        return Result.new(code, numeric, 0f32, 0f32)
      end
    end

    if nginx = headers["X-Country-Code"]?
      code = nginx.downcase
      if numeric = COUNTRY_CODES[code]?
        return Result.new(code, numeric, 0f32, 0f32)
      end
    end

    fetch_from_ip(ip)
  rescue ex
    rlog "[geoloc] #{ex.message}", Ansi::LYELLOW
    unknown
  end

  private def self.fetch_from_ip(ip : String) : Result
    url_ip = private_ip?(ip) ? "" : ip
    response = HTTP::Client.get(
      "http://ip-api.com/line/#{url_ip}?fields=status,message,countryCode,lat,lon"
    )

    lines = response.body.split("\n")
    return unknown unless lines[0]? == "success"

    country = (lines[1]? || "xx").downcase
    lat     = lines[2]?.try(&.to_f32?) || 0f32
    lon     = lines[3]?.try(&.to_f32?) || 0f32
    numeric = COUNTRY_CODES[country]? || COUNTRY_CODES["xx"]

    Result.new(country, numeric, lat, lon)
  rescue ex
    rlog "[geoloc] ip-api failed: #{ex.message}", Ansi::LYELLOW
    unknown
  end

  private def self.private_ip?(ip : String) : Bool
    ip.empty? ||
    ip == "0" ||
    ip.starts_with?("127.") ||
    ip.starts_with?("10.") ||
    ip.starts_with?("192.168.") ||
    ip.starts_with?("172.")
  end

  private def self.unknown : Result
    Result.new("xx", COUNTRY_CODES["xx"], 0f32, 0f32)
  end
end
