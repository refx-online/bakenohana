require "redis"
require "../config"
require "../log"

module RedisService
  @@redis : Redis? = nil
  @@sub   : Redis? = nil

  def self.init
    uri = URI.parse(Config.redis_url)
    host     = uri.host || "localhost"
    port     = uri.port || 6379
    password = uri.password

    @@redis = Redis.new(host: host, port: port, password: password)
    @@sub   = Redis.new(host: host, port: port, password: password)
    rlog "redis connected (#{host}:#{port})", Ansi::LCYAN
  end

  def self.redis : Redis
    @@redis.not_nil!
  end

  def self.sub : Redis
    @@sub.not_nil!
  end

  # sorted set helpers

  def self.zadd(key : String, score : Float64, member : Int32)
    redis.zadd(key, score.to_s, member.to_s)
  end

  def self.zrem(key : String, member : Int32)
    redis.zrem(key, member.to_s)
  end

  # 0-based rank from top (highest score = rank 0)
  def self.zrevrank(key : String, member : Int32) : Int64?
    redis.zrevrank(key, member.to_s).as?(Int64)
  end

  def self.publish(channel : String, message : String)
    redis.publish(channel, message)
  end

  def self.leaderboard_key(mode : Int32) : String
    "bancho:leaderboard:#{mode}"
  end

  def self.country_leaderboard_key(mode : Int32, country : String) : String
    "bancho:leaderboard:#{mode}:#{country.downcase}"
  end
end
