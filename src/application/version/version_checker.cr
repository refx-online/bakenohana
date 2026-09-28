require "http/client"
require "json"
require "../../infrastructure/logging/logger"

module VersionChecker
  OSU_API_V2_CHANGELOG_URL = "https://osu.ppy.sh/api/v2/changelog"

  @@cache = {} of String => Set(String)
  @@last_fetch = {} of String => Time
  @@mutex = Mutex.new
  CACHE_TTL = 1.hour

  def self.allowed?(date_str : String, stream : String, is_refx : Bool) : Bool
    return true if is_refx

    stream_key = normalize_stream(stream)
    versions = fetch_allowed_versions(stream_key)
    if versions.nil?
      rlog "[version] no version list available, allowing #{date_str} (fail-open)", Ansi::LYELLOW
      return true
    end

    versions.includes?(date_str)
  end

  private def self.normalize_stream(stream : String) : String
    case stream
    when "stable"
      "stable40"
    when "beta", "cuttingedge", "dev"
      "cuttingedge"
    when "tourney"
      "stable40"
    else
      "stable40"
    end
  end

  private def self.fetch_allowed_versions(stream : String) : Set(String)?
    @@mutex.synchronize do
      last = @@last_fetch[stream]?
      if last && (Time.utc - last) < CACHE_TTL && @@cache[stream]?
        return @@cache[stream]
      end
    end

    versions = fetch_from_api(stream)
    if versions.nil?
      # NOTE: api hiccup — reuse the last known list instead of fail-opening
      # to "allow everything". only fail open when we never fetched once.
      return @@mutex.synchronize { @@cache[stream]? }
    end

    @@mutex.synchronize do
      @@cache[stream] = versions
      @@last_fetch[stream] = Time.utc
    end

    versions
  end

  private def self.fetch_from_api(stream : String) : Set(String)?
    streams_to_check = if stream == "tourney"
                         ["stable40", "cuttingedge"]
                       else
                         [stream]
                       end

    all_versions = Set(String).new

    streams_to_check.each do |s|
      versions = fetch_single_stream(s)
      return nil if versions.nil?
      all_versions.concat(versions)
    end

    all_versions
  end

  private def self.fetch_single_stream(stream : String) : Set(String)?
    uri = URI.parse("#{OSU_API_V2_CHANGELOG_URL}?stream=#{stream}")

    # NOTE: unbounded by default — a hung api call would stall logins.
    client = HTTP::Client.new(uri)
    client.connect_timeout = 5.seconds
    client.read_timeout = 10.seconds
    response = client.get(uri.request_target)
    return nil unless response.success?

    body = JSON.parse(response.body)
    builds = body["builds"].as_a

    versions = Set(String).new

    builds.each do |build|
      version_str = build["version"].as_s
      versions.add(version_str)

      changelog_entries = build["changelog_entries"].as_a
      has_major = changelog_entries.any? do |entry|
        entry["major"]?.try(&.as_bool) || false
      end

      break if has_major
    end

    versions
  rescue ex
    nil
  end
end
