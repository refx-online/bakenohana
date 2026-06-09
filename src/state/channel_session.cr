require "../domain/channel/channel"
require "../persistence/repositories/channel"
require "../infrastructure/logging/logger"

module ChannelSession
  @@channels = Array(Channels).new
  @@mutex = Mutex.new

  # HACK: dup to avoid holding lock during iter
  def self.each(&block : Channels ->)
    channels_ = @@mutex.synchronize { @@channels.dup }
    channels_.each do |channel|
      yield channel
    end
  end

  def self.includes?(o : Channels | String) : Bool
    @@mutex.synchronize do
      case o
      when String
        @@channels.any? { |c| c.name == o }
      when Channel
        @@channels.includes?(o)
      else
        false
      end
    end
  end

  def self.[](name : String) : Channels?
    get_by_name(name)
  end

  def self.[]?(name : String) : Channels?
    get_by_name(name)
  end

  def self.to_s(io)
    @@mutex.synchronize do
      io << "["
      @@channels.join(io, ", ") { |c, io| io << c.r_name }
      io << "]"
    end
  end

  def self.get_by_name(name : String) : Channels?
    @@mutex.synchronize do
      @@channels.find { |c| c.r_name == name }
    end
  end

  def self.append(channel : Channels) : Nil
    @@mutex.synchronize do
      @@channels << channel
    end
  end

  def self.remove(channel : Channels) : Nil
    @@mutex.synchronize do
      @@channels.delete(channel)
    end
  end

  def self.size : Int32
    @@mutex.synchronize { @@channels.size }
  end

  def self.empty? : Bool
    @@mutex.synchronize { @@channels.empty? }
  end

  def self.auto_join : Array(Channels)
    @@mutex.synchronize do
      @@channels.select(&.auto_join)
    end
  end

  def self.prepare : Nil
    rlog "fetching channels from sql.", Ansi::LCYAN

    ChanRepo.fetch_all.each do |row|
      append(Channels.new(
        name: row.name,
        topic: row.topic,
        read_priv: Privileges.new(row.read_priv),
        write_priv: Privileges.new(row.write_priv),
        auto_join: row.auto_join,
        instance: false
      ))
    end

    rlog "loaded #{size} channels from database.", Ansi::LGREEN
  end
end

class Match
  def host : Player?
    PlayerSession.get(id: @host_id)
  end
end
