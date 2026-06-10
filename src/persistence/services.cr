require "dotenv"
require "./database"
require "../infrastructure/ai/openai_client"
require "../infrastructure/config/config"

module Services
  @@mysql : Database? = nil
  @@ai_client : AI::OpenAIClient? = nil

  def self.init
    @@mysql = Database.new(
        "mysql://#{ENV["DB_USER"]}:#{ENV["DB_PASS"]}@#{ENV["DB_HOST"]}:#{ENV["DB_PORT"]}/#{ENV["DB_NAME"]}"
    )

    if Config.ai_enabled
      @@ai_client = AI::OpenAIClient.new
    end
  end

  def self.db : Database
    @@mysql.not_nil!
  end

  def self.ai_client : AI::OpenAIClient
    @@ai_client.not_nil!
  end
end
