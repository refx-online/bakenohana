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
    # Private/loopback clients carry no geo meaning (and the API would just
    # see our own egress IP) — skip the call entirely. It has no DNS
    # timeout cover, so a stall here hangs logins.
    return unknown if private_ip?(ip)
    client = HTTP::Client.new(URI.parse("http://ip-api.com"))
    client.connect_timeout = 3.seconds
    client.read_timeout = 3.seconds
    body = client.get("/line/#{ip}?fields=status,message,countryCode,lat,lon").body

    lines = body.split("\n")
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
