require "../domain/channel/channel"
require "../persistence/repositories/channel"

module PlayerSession
  @@players = Hash(String, Player).new
  @@bot : Player = Player.new( # TODO: use db
    id: 1,
    username: "boat",
    token: "_bot",
    ip: "0",
    login_time: Time.utc,
    priv: Privileges::BOAT
  )
  @@mutex = Mutex.new

  def self.add(token : String, p : Player)
    @@mutex.synchronize do
      @@players[token] = p
    end
  end

  def self.get(token : String) : Player?
    @@mutex.synchronize do
      @@players[token]?
    end
  end

  def self.get(*, token : String? = nil, id : Int32? = nil, username : String? = nil) : Player?
    @@mutex.synchronize do
      if token
        @@players[token]?
      elsif id
        return @@bot if id == 1
        @@players.values.find { |player| player.id == id }
      elsif username
        return @@bot if username == "boat" # trolage
        @@players.values.find { |player| player.username == username }
      else
        nil
      end
    end
  end

  def self.bot : Player
    @@bot
  end

  def self.remove(token : String)
    @@mutex.synchronize do
      @@players.delete(token)
    end
  end

  # bot yielded outside lock intentionally — bot is immutable after init
  def self.each(&block : Player, String ->)
    yield @@bot, @@bot.token
    players_ = @@mutex.synchronize { @@players.dup }
    players_.each do |token, player|
      yield player, token
    end
  end

  def self.restricted : Set(Player)
    @@mutex.synchronize do
      @@players.values.select(&.restricted).to_set
    end
  end

  def self.unrestricted_count : Int32
    @@mutex.synchronize do
      @@players.values.count { |p| !p.restricted } + 1 # +1 for bot
    end
  end

  def self.unrestricted : Set(Player)
    @@mutex.synchronize do
      res = @@players.values.reject(&.restricted).to_set
      res.add(@@bot)
      res
    end
  end
end
