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

  def self.discord_rank_webhook : String?
    ENV["DISCORD_RANK_WEBHOOK"]?
  end

  def self.omajinai_url : String
    ENV["OMAJINAI_URL"]? || "http://localhost:5000"
  end

  def self.redis_url : String
    ENV["REDIS_URL"]? || "redis://localhost:6379"
  end

  def self.enable_old_client_check : Bool
    ENV["ENABLE_OLD_CLIENT_CHECK"]? == "true"
  end

  def self.ai_enabled : Bool
    ENV["AI_ENABLED"]? == "true"
  end

  def self.ai_base_url : String
    ENV["AI_BASE_URL"]? || "https://api.openai.com/v1"
  end

  def self.ai_api_key : String
    ENV["AI_API_KEY"]? || ""
  end

  def self.ai_model : String
    ENV["AI_MODEL"]? || "gpt-3.5-turbo"
  end

  def self.ai_temperature : Float64
    ENV["AI_TEMPERATURE"]?.try(&.to_f) || 0.7
  end

  def self.ai_max_tokens : Int32
    ENV["AI_MAX_TOKENS"]?.try(&.to_i) || 150
  end

  def self.ai_system_prompt : String
    ENV["AI_SYSTEM_PROMPT"]? || "You are a helpful osu! bot assistant. Keep responses concise and friendly."
  end
end

# unhandled conf
# PORT=
# DB_HOST=
# DB_PORT=
# DB_NAME=
# DB_USER=
# DB_PASS=
