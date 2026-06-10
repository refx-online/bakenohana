require "./stats"
require "./status"
require "../channel/channel"
require "../match/match"

require "../../shared/constants/priv"
require "../../shared/constants/presence_filter"
require "../../transport/protocol/packets"
require "../../persistence/repositories/relationship"
require "../../persistence/repositories/user"
require "../../persistence/repositories/stats"
require "../../infrastructure/redis/redis_client"
require "../../infrastructure/logging/logger"
require "../../state/match_session"

class Player
  getter token : String
  getter username : String
  getter ip : String
  getter login_time : Time
  getter id : Int32

  @last_recv_time : Time = Time.utc
  @last_recv_mut = Mutex.new

  property stats : PlayerStats = PlayerStats.new
  property status : PlayerStatus = PlayerStatus.new

  property priv : Privileges
  property silence_end : Int64 = 0_i64
  property pm_private : Bool = false
  property away_msg : String? = nil
  property pres_filter : PresenceFilter = PresenceFilter::All
  property last_np : Tuple(Int32, Gamemode)? = nil
  property refx : Bool = false
  property refx_lb : Int32 = 0

  property match : Match? = nil
  property in_lobby : Bool = false

  @friends = Set(Int32).new
  @friends_mut = Mutex.new

  @channels = Array(Channels).new
  @channels_mut = Mutex.new

  property spectators : Array(Player) = [] of Player
  property spectating : Player? = nil

  @queue = IO::Memory.new
  @queue_mut = Mutex.new

  def initialize(
    @id : Int32,
    @username : String,
    @token : String,
    @ip : String,
    @login_time : Time,
    @priv : Privileges,
    @silence_end : Int64 = 0_i64
  )
    @priv = priv
  end

  def enqueue(data : Bytes)
    @queue_mut.synchronize do
      @queue.write data
    end

    if data.size >= 2
      packet_id = IO::ByteFormat::LittleEndian.decode(UInt16, data[0, 2])
      rlog "Server sent packet #{packet_id} to #{@username}", Ansi::LCYAN
    end
  end

  def dequeue : Bytes
    @queue_mut.synchronize do
      buf = @queue.to_slice
      @queue = IO::Memory.new
      buf
    end
  end

  def last_recv_time
    @last_recv_mut.synchronize { @last_recv_time }
  end

  def last_recv_time=(time : Time)
    @last_recv_mut.synchronize { @last_recv_time = time }
  end

  def friends : Set(Int32)
    @friends_mut.synchronize { @friends.dup }
  end

  def remaining_silence : Int32
    [0_i64, @silence_end - Time.utc.to_unix].max.to_i32
  end

  def silenced? : Bool
    remaining_silence > 0
  end

  def update_offset(offset : Int32)
    @status.utc_offset = offset
  end

  def load_stats : Nil
    row = StatsRepo.fetch_one(@id, @status.mode.value.to_i)
    return unless row

    @stats.pp          = row.pp.to_i32
    @stats.acc         = row.acc.to_f64
    @stats.plays       = row.plays.to_i32
    @stats.tscore      = row.tscore.to_i64
    @stats.rscore      = row.rscore.to_i64
    @stats.max_combo   = row.max_combo.to_i32
    @stats.total_hits  = row.total_hits.to_i32
    @stats.global_rank = 0
  end

  def update_leaderboards : Nil
    return if restricted

    mode = @status.mode.value.to_i
    pp   = @stats.pp.to_f64

    RedisService.zadd(RedisService.leaderboard_key(mode), pp, @id)

    unless @status.country.empty?
      RedisService.zadd(RedisService.country_leaderboard_key(mode, @status.country), pp, @id)
    end

    global_rank  = RedisService.zrevrank(RedisService.leaderboard_key(mode), @id)
    @stats.global_rank = global_rank ? (global_rank + 1).to_i32 : 0
  end

  def remove_from_leaderboards : Nil
    Gamemode.values.each do |gm|
      next unless Gamemode.valid_gamemodes.includes?(gm)
      mode = gm.value.to_i
      RedisService.zrem(RedisService.leaderboard_key(mode), @id)
      RedisService.zrem(RedisService.country_leaderboard_key(mode, @status.country), @id) unless @status.country.empty?
    end
  end

  def client_priv : ClientPrivileges # TODO: cache?
    ret = ClientPrivileges::None
    ret |= ClientPrivileges::PLAYER     if @priv & Privileges::UNRESTRICTED != 0
    ret |= ClientPrivileges::MODERATOR  if @priv & Privileges::MODERATOR != 0 || @priv & Privileges::ADMINISTRATOR != 0
    ret |= ClientPrivileges::DEVELOPER  if @priv & Privileges::DEVELOPER != 0
    ret |= ClientPrivileges::PEPPY      if @priv & Privileges::PEPPY != 0
    ret
  end

  def restricted : Bool
    !@priv.includes?(Privileges::UNRESTRICTED)
  end

  def add_friend(player : Player) : Nil
    if @friends_mut.synchronize { @friends.includes?(player.id) }
      rlog "#{@username} tries to add #{player.username}, whos already their friend!", Ansi::LYELLOW
      return
    end

    @friends_mut.synchronize { @friends.add(player.id) }

    RelationshipRepo.create(@id, player.id)

    rlog "#{@username} friended #{player.username}."
  end

  def remove_friend(player : Player) : Nil
    unless @friends_mut.synchronize { @friends.includes?(player.id) }
      rlog "#{@username} tries to unfriend #{player.username}, whos not their friend!", Ansi::LYELLOW
      return
    end

    @friends_mut.synchronize { @friends.delete(player.id) }

    RelationshipRepo.delete(@id, player.id)

    rlog "#{@username} unfriended #{player.username}."
  end

  def get_relationship : Nil
    relation = RelationshipRepo.fetch_all_for(@id)

    @friends_mut.synchronize do
      @friends.clear
      relation.each do |rel|
        case rel.type
        when "friend"
          @friends.add(rel.user2)
        when "block"
          # TODO: Add blocks set and mutex
          # @blocks.add(user2_id)
        end
      end
    end
  end

  private def set_priv(priv : Privileges) : Nil
    @priv = priv
    UserRepo.update(
      id: @id,
      priv: @priv.value
    )

    rlog "updated #{@username} (#{@id}) priv to #{@priv.to_s}"
  end

  def add_priv(priv : Privileges) : Nil
    set_priv(@priv | priv)
  end

  def rem_priv(priv : Privileges) : Nil
    set_priv(@priv & ~priv)
  end

  def logout
    remove_from_leaderboards

    leave_match if @match

    if h = @spectating
      h.remove_spectator(self)
    end

    while !@channels_mut.synchronize { @channels.empty? }
      first_channel = @channels_mut.synchronize { @channels.first? }
      break unless first_channel
      leave_channel(first_channel, kick: false)
    end

    PlayerSession.remove(@token)

    logout_packet = Packets.logout(@id)
    PlayerSession.each do |other_player, _|
      next if other_player.token == @token
      other_player.enqueue(logout_packet)
    end

    @queue_mut.synchronize do
      @queue = IO::Memory.new
    end

    rlog "#{@username} (#{@id}) logged out"
  end

  # channel stuff

  def channels : Array(Channels)
    @channels_mut.synchronize { @channels.dup }
  end

  def add_channel(channel : Channels)
    @channels_mut.synchronize do
      @channels << channel unless @channels.includes?(channel)
    end
  end

  def remove_channel(channel : Channels)
    @channels_mut.synchronize do
      @channels.delete(channel)
    end
  end

  def join_channel(channel : Channels) : Bool
    if channel.includes?(self) ||
      !channel.can_read?(@priv)
      return false
    end

    channel.append(self)

    add_channel(channel)

    enqueue(Packets.channel_join(channel.name))

    chan_info_packet = Packets.channel_info(channel.name, channel.topic, channel.player_count)

    if channel.instance
      channel.players.each do |p|
        p.enqueue(chan_info_packet)
      end
    else
      PlayerSession.each do |p, _|
        if channel.can_read?(p.priv)
          p.enqueue(chan_info_packet)
        end
      end
    end

    true
  end

  def leave_channel(channel : Channels, kick : Bool = true) : Nil
    return unless channel.includes?(self)

    channel.remove(self)

    remove_channel(channel)

    if kick
      enqueue(Packets.channel_kick(channel.name))
    end

    chan_info_packet = Packets.channel_info(channel.name, channel.topic, channel.player_count)

    if channel.instance
      channel.players.each do |p|
        p.enqueue(chan_info_packet)
      end
    else
      PlayerSession.each do |p, _|
        if channel.can_read?(p.priv)
          p.enqueue(chan_info_packet)
        end
      end
    end
  end

  def send_msg(msg : String, sender : Player, chan : Channel | Nil = nil) : Nil
    target = chan.try(&.name) || @username

    data = Packets.send_message(
      sender.username,
      msg,
      target,
      sender.id
    )

    enqueue(data)
  end

  def resolve_mode(mode : UInt8, mods : UInt32) : Tuple(UInt8, UInt32)
    if @refx
      case @refx_lb
      when 1, 2 then return {12_u8, mods} # cheat/cheatselectedmod
      when 5, 6 then return {16_u8, mods} # cheatcheat/cheatcheatselectedmod
      end
      return {mode, mods}
    end

    if (mods & Mods::TOUCHSCREEN.value) != 0
      return {20_u8, mods}
    end

    if (mods & Mods::RELAX.value) != 0
      if mode == 3
        mods &= ~Mods::RELAX.value
      elsif mode <= 2
        mode = (mode + 4).to_u8
      elsif mode >= 4 && mode <= 6
        # already in rx range, keep as-is
      else
        mods &= ~Mods::RELAX.value
      end
    elsif (mods & Mods::AUTOPILOT.value) != 0
      if mode == 0
        mode = 8_u8
      else
        mods &= ~Mods::AUTOPILOT.value
      end
    end

    {mode, mods}
  end

  # spectating shit

  def add_spectator(player : Player) : Nil
    chan_name = "#spec_#{@id}"

    spec_chan = ChannelSession.get_by_name(chan_name)
    unless spec_chan
      spec_chan = Channels.new(
        name: chan_name,
        topic: "#{@username}'s spectator channel.",
        auto_join: false,
        instance: true
      )

      join_channel(spec_chan)
      ChannelSession.append(spec_chan)
    end

    unless player.join_channel(spec_chan)
      rlog "#{@username} failed to join #{spec_chan}?", Ansi::LYELLOW
      return
    end

    player_joined = Packets.f_spectator_joined(player.id)
    @spectators.each do |spectator|
      spectator.enqueue(player_joined)
      player.enqueue(Packets.f_spectator_joined(spectator.id))
    end
    enqueue(Packets.spectator_joined(player.id))

    @spectators << player
    player.spectating = self

    player.enqueue(Packets.user_stats(self))

    rlog "#{player.username} is now spectating #{@username}"
  end

  def remove_spectator(player : Player) : Nil
    @spectators.delete(player)
    player.spectating = nil

    channel = ChannelSession.get_by_name("#spec_#{@id}")
    raise "missing channel?" unless channel

    player.leave_channel(channel)

    if @spectators.empty?
      leave_channel(channel)
    else
      channel_info = Packets.channel_info(
        channel.name,
        channel.topic,
        channel.player_count
      )

      fellow = Packets.f_spectator_left(player.id)
      enqueue(channel_info)

      @spectators.each do |spectator|
        spectator.enqueue(fellow + channel_info)
      end
    end

    enqueue(Packets.spectator_left(player.id))
    rlog "#{player.username} is no longer spectating #{@username}"
  end

  # multiplayer

  def join_match(match : Match, passwd : String) : Bool
    if @match
      enqueue(Packets.match_join_fail)
      return false
    end

    if self != match.host
      if passwd != match.passwd
        rlog "#{@username} tried to join #{match.name} w/ wrong pw.", Ansi::LYELLOW
        enqueue(Packets.match_join_fail)
        return false
      end

      slot_id = match.get_free
      if slot_id.nil?
        rlog "#{@username} tried to join full match.", Ansi::LYELLOW
        enqueue(Packets.match_join_fail)
        return false
      end
    else
      slot_id = 0
    end

    unless join_channel(match.chat)
      rlog "#{@username} failed to join #{match.chat}.", Ansi::LYELLOW
      return false
    end

    lobby = ChannelSession.get_by_name("#lobby")
    if lobby && channels.includes?(lobby)
      leave_channel(lobby)
    end

    slot = match.slots[slot_id]

    if match.team_type == MatchTeamTypes::TeamVs || match.team_type == MatchTeamTypes::TagTeamVs
      slot.team = MatchTeams::Red
    end

    slot.status = SlotStatus::NotReady
    slot.player = self
    @match = match

    enqueue(Packets.match_join_success(match))
    match.enqueue_state

    true
  end

  def leave_match : Nil
    m = @match
    unless m
      return
    end

    slot = m.get_slot(self)
    return unless slot

    new_status = slot.status == SlotStatus::Locked ? SlotStatus::Locked : SlotStatus::Open
    slot.reset(new_status)

    leave_channel(m.chat)

    if m.slots.all?(&.empty?)
      rlog "Match #{m.name} (#{m.id}) is now empty, disposing."
      MatchSession.remove(m)
      lobby = ChannelSession.get_by_name("#lobby")
      lobby.try(&.enqueue(Packets.dispose_match(m.id)))
    else
      if self.same?(m.host)
        m.slots.each do |s|
          if s.player
            m.host_id = s.player.not_nil!.id
            m.host.try(&.enqueue(Packets.match_transfer_host))
            break
          end
        end
      end

      m.enqueue_state
    end

    @match = nil
  end
end
