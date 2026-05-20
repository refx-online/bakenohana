module Config
  def self.debug : Bool
    ENV["DEBUG"]? == "true"
  end

  def self.domain : String
    ENV["DOMAIN"]? || "localhost"
  end

  def self.osu_api_key : String
    ENV["OSU_API_KEY"]? || "" # for requesting map
  end

  def self.boat_prefix : String
    ENV["BOAT_PREFIX"]? || "?"
  end

  def self.map_api : String
    ENV["MAP_MIRROR_API"]? || ""
  end

  def self.omajinai_url : String
    ENV["OMAJINAI_URL"]? || "http://localhost:5000"
  end

  def self.redis_url : String
    ENV["REDIS_URL"]? || "redis://localhost:6379"
  end
end

# unhandled conf
# PORT=
# DB_HOST=
# DB_PORT=
# DB_NAME=
# DB_USER=
# DB_PASS=