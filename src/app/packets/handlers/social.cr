require "../../state/sessions"

class AddFriendPacket < BasePacket
  def initialize(reader : BanchoPacketReader)
    super(reader)
    @id = reader.read_i32
  end

  def handle(p : Player)
    target = PlayerSession.get(id: @id)
    unless target
      rlog "#{p.username} tries to add offline player: (#{@id})", Ansi::LYELLOW
      return
    end
    p.add_friend(target)
  end
end

class RemoveFriendPacket < BasePacket
  def initialize(reader : BanchoPacketReader)
    super(reader)
    @id = reader.read_i32
  end

  def handle(p : Player)
    target = PlayerSession.get(id: @id)
    unless target
      rlog "#{p.username} tries to remove offline player: (#{@id})", Ansi::LYELLOW
      return
    end
    p.remove_friend(target)
  end
end

register(ClientPackets::FRIEND_ADD,    AddFriendPacket)
register(ClientPackets::FRIEND_REMOVE, RemoveFriendPacket)
