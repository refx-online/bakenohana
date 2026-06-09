require "../domain/match/match"

module MatchSession
  MAX_MATCHES = 64

  @@matches = Array(Match?).new(MAX_MATCHES, nil)
  @@mutex = Mutex.new

  def self.get_free : Int32?
    @@mutex.synchronize do
      @@matches.each_with_index do |m, i|
        return i if m.nil?
      end
      nil
    end
  end

  def self.[](id : Int32) : Match?
    return nil unless 0 <= id < MAX_MATCHES
    @@mutex.synchronize { @@matches[id] }
  end

  def self.[]=(id : Int32, match : Match?) : Nil
    return unless 0 <= id < MAX_MATCHES
    @@mutex.synchronize { @@matches[id] = match }
  end

  def self.remove(match : Match) : Nil
    @@mutex.synchronize { @@matches[match.id] = nil }
  end

  def self.each(&block : Match ->)
    matches_ = @@mutex.synchronize { @@matches.dup }
    matches_.each do |m|
      yield m if m
    end
  end

  def self.count : Int32
    @@mutex.synchronize { @@matches.count { |m| !m.nil? } }
  end
end
