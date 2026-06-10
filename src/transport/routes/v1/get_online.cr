require "../../../state/player_session"

module Api::V1
  def self.register_get_online
    get "/api/v1/get_online" do |env|
      env.response.content_type = "text/plain"

      players = [] of String
      bot_line = ""

      PlayerSession.each do |player, _|
        if player.id == PlayerSession.bot.id
          bot_line = "#{player.username} (bot)"
          next
        end

        line = player.username
        if m = player.match
          line += " [match: #{m.name}]"
        end

        players << line
      end

      output = players.join('\n')
      output += "\n---\n#{bot_line}" unless bot_line.empty?
      output
    end
  end
end
