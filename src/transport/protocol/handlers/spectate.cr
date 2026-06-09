require "../../../state/player_session"

class StartSpectatingPacket < BasePacket
  def initialize(reader : BanchoPacketReader)
    super(reader)
    @id = reader.read_i32
  end

  def handle(p : Player) : Nil
    target = PlayerSession.get(id: @id)
    unless target
      rlog "#{p.username} tried to spectate non-existent id #{@id}", Ansi::LYELLOW
      return
    end

    if host = p.spectating
      if host == target
        target.enqueue(Packets.spectator_joined(p.id))
        f_joined = Packets.f_spectator_joined(p.id)
        target.spectators.each do |spec|
          spec.enqueue(f_joined) unless spec == p
        end
        return
      end
      host.remove_spectator(p)
    end

    target.add_spectator(p)
  end
end

class StopSpectatingPacket < BasePacket
  def handle(p : Player)
    p.spectating.try &.remove_spectator(p)
  end
end

class SpectateFramesPacket < BasePacket
  def initialize(reader : BanchoPacketReader)
    super(reader)
    @frames = reader.read_raw
  end

  def handle(p : Player) : Nil
    frames_packet = Packets.spectator_frames(@frames)
    p.spectators.each &.enqueue(frames_packet)
  end
end

class CantSpectatePacket < BasePacket
  def handle(p : Player) : Nil
    host = p.spectating
    unless host
      rlog "#{p.username} sent can't spectate while not spectating?", Ansi::LRED
      return
    end

    data = Packets.spectator_cant_spectate(p.id)
    host.enqueue(data)
    host.spectators.each &.enqueue(data)
  end
end

register(ClientPackets::START_SPECTATING, StartSpectatingPacket)
register(ClientPackets::STOP_SPECTATING,  StopSpectatingPacket)
register(ClientPackets::SPECTATE_FRAMES,  SpectateFramesPacket)
register(ClientPackets::CANT_SPECTATE,    CantSpectatePacket)
