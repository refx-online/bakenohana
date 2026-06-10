require "http/client"
require "json"
require "../config/config"

module AI
  struct Message
    include JSON::Serializable

    property role : String
    property content : String

    def initialize(@role : String, @content : String)
    end
  end

  struct Choice
    include JSON::Serializable

    property message : Message
    property finish_reason : String?
    property index : Int32
  end

  struct CompletionResponse
    include JSON::Serializable

    property id : String
    property object : String
    property created : Int64
    property model : String
    property choices : Array(Choice)
  end

  struct CompletionRequest
    include JSON::Serializable

    property model : String
    property messages : Array(Message)
    property temperature : Float64?
    property max_tokens : Int32?
    property stream : Bool

    def initialize(@model : String, @messages : Array(Message), @temperature : Float64? = nil, @max_tokens : Int32? = nil, @stream : Bool = false)
    end
  end

  class OpenAIClient
    @base_url : String
    @api_key : String
    @model : String
    @temperature : Float64
    @max_tokens : Int32

    def initialize(
      base_url : String = Config.ai_base_url,
      api_key : String = Config.ai_api_key,
      model : String = Config.ai_model,
      temperature : Float64 = Config.ai_temperature,
      max_tokens : Int32 = Config.ai_max_tokens
    )
      @base_url = base_url.chomp("/")
      @api_key = api_key
      @model = model
      @temperature = temperature
      @max_tokens = max_tokens
    end

    def chat(user_message : String, system_prompt : String? = nil) : String?
      messages = [] of Message

      if system_prompt
        messages << Message.new("system", system_prompt)
      end

      messages << Message.new("user", user_message)

      request_body = CompletionRequest.new(
        model: @model,
        messages: messages,
        temperature: @temperature,
        max_tokens: @max_tokens,
        stream: false
      )

      uri = URI.parse("#{@base_url}/chat/completions")

      headers = HTTP::Headers{
        "Content-Type"  => "application/json",
        "Authorization" => "Bearer #{@api_key}",
      }

      response = HTTP::Client.post(
        uri,
        headers: headers,
        body: request_body.to_json
      )

      unless response.success?
        rlog "[AI] request failed: #{response.status_code} #{response.body}", Ansi::LRED
        return nil
      end

      completion = CompletionResponse.from_json(response.body)
      choice = completion.choices.first?

      choice.try(&.message.content.strip)
    rescue ex
      rlog "[AI] error: #{ex.message}", Ansi::LRED
      nil
    end
  end
end
