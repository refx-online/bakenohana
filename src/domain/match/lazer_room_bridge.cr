require "json"

require "../../infrastructure/logging/logger"
require "../../infrastructure/redis/redis_client"
require "../../state/channel_session"
require "../../state/match_session"
require "../../state/player_session"
require "../../transport/protocol/packets"

# MPv2 -> MPv1 room projection.
#
# speedforce owns every lazer room; this turns a published projection of one
# into a `Match` so **stock** stable can see and join it. Nothing here is
# required for lazer clients, which keep talking to their own hub directly.
#
# Why this exists at all
# ----------------------
# stable speaks MPv1 and has never heard of SignalR. The refx-stable fork has a
# client-side MPv2 stack (`osu!/Online/MP/`), but making every stock client
# carry a translation layer is not a server's job -- so the translation lives
# here instead, where one process serves every unmodified client.
#
# One writer, one owner
# ---------------------
# Only speedforce creates rooms. This side never creates one; it materialises
# what was published and can update or dispose it. Two writers on one room
# would need ordering that neither protocol offers, and MPv1 has no
# reconcile-on-connect to recover with.
#
# What is *not* bridged yet
# -------------------------
# - **Mods.** lazer sends a list of `{"acronym": "HR"}` objects; bancho needs a
#   `Mods` bitmask. No conversion is attempted rather than a guessed one, so a
#   projected room starts NOMOD. `ponytail: mods are not projected -- map the
#   acronyms to Mods bits once someone plays a projected room with mods and says
#   which bits lazer's names correspond to.`
# - **Playlist.** MPv1 has no queue at all: its `Match` carries a single
#   `map_id`. The projection sends only the room's *current* item, which the
#   host controls, so "host picks the map" holds on both protocols.
# - **Slot occupants** are projected as bare user ids (`Slot#remote_id`), not as
#   sessions: the MPv1 wire carries only an id and the client resolves the name
#   from its own lobby, where lazer users already appear via
#   `lazer_presence.cr`. Nothing can be sent *to* such an occupant, so a
#   projected seat is display-only.
module LazerRoomBridge
  extend self

  # lazer room id -> the MPv1 match id it was given.
  #
  # These are different numbering spaces and cannot be conflated: lazer room ids
  # are a monotonic counter (any size), while `MatchSession` is a fixed 64-slot
  # array whose `[]=` silently ignores an out-of-range index. Storing a match
  # under the lazer room id therefore registers nothing at all -- and still logs
  # as a success, which is how this was caught.
  @@projected = Hash(Int32, Int32).new
  @@lock = Mutex.new

  # Same channel speedforce's `app/signalr/bridge.py` publishes on.
  CHANNEL = "refx:mpv2:room"

  # Where a stable player's action in a projected room is *requested*. Separate
  # from `CHANNEL` because a pub/sub subscriber cannot distinguish its own echo
  # from a peer's, so one channel would make every action bounce back into the
  # handler that produced it.
  INTENT_CHANNEL = "refx:mpv2:intent"

  # `Match` allocates exactly 16 (match.cr), and the projection sends 16.
  MAX_SLOTS = 16

  def handle(payload : String) : Nil
    data = JSON.parse(payload)

    room_id = data["room_id"]?.try(&.as_i)
    return unless room_id

    # Value, not presence: `data["closed"]?` is truthy for a key holding
    # `false` too, so any projection that sets the field explicitly would
    # dispose a live room.
    if data["closed"]?.try(&.as_bool) || false
      dispose(room_id)
      return
    end

    upsert(room_id, data)
  rescue ex : JSON::ParseException
    # A malformed projection must not kill the subscribe loop -- every other
    # channel on this connection depends on it staying up.
    rlog "[mpv2] bad projection payload: #{ex.message}", Ansi::LYELLOW
  rescue ex
    rlog "[mpv2] projection error: #{ex.message}", Ansi::LRED
    rlog ex.backtrace.join("\n"), Ansi::LRED
  end

  private def dispose(room_id : Int32) : Nil
    match_id = @@lock.synchronize { @@projected.delete(room_id) }

    if match_id
      if match = MatchSession[match_id]
        MatchSession.remove(match)
        ChannelSession.remove(match.chat) if match.chat

        PlayerSession.each do |player, _|
          player.enqueue(Packets.dispose_match(match.id)) if player.in_lobby
        end

        rlog "[mpv2] disposed projected match #{match.id} (lazer room #{room_id})", Ansi::LBLUE
      end
    end
  end

  private def upsert(room_id : Int32, data : JSON::Any) : Nil
    if match_id = @@lock.synchronize { @@projected[room_id]? }
      if existing = MatchSession[match_id]
        apply(existing, data)
        broadcast(existing)
        # `broadcast` only reaches lobby browsers. Stable players already seated
        # in this match sit on its channel, so they are never told a projected
        # seat filled or emptied -- the slot rendered blank until they
        # rejoined. `UPDATE_MATCH` is what refx-stable repaints from
        # (`ClientSideMatch`), and it is already what a stable-initiated slot
        # move sends, so no new packet id is needed. `lobby: false` because
        # `broadcast` has already covered the lobby.
        existing.enqueue_state(lobby: false)
        return
      end
      # The match was disposed while the lazer room stayed open, so rebuild it
      # from the room rather than leaving stable with nothing.
      @@lock.synchronize { @@projected.delete(room_id) }
    end

    created = create(room_id, data)
    return unless created

    created.projected = true
    MatchSession[created.id] = created
    @@lock.synchronize { @@projected[room_id] = created.id }
    ChannelSession.append(created.chat)
    seat(created, data)
    broadcast(created)

    rlog "[mpv2] projected lazer room #{room_id} as match #{created.id} #{created.name.inspect}", Ansi::LCYAN
  end

  private def create(room_id : Int32, data : JSON::Any) : Match?
    # MPv1 match ids index a 64-slot array, so a lazer room id (a monotonic
    # counter, unbounded) cannot be used directly -- it would be rejected as out
    # of range and the room would silently never appear.
    id = MatchSession.get_free
    unless id
      rlog "[mpv2] no free match slot for lazer room #{room_id}, not projected", Ansi::LYELLOW
      return nil
    end

    name = data["name"]?.try(&.as_s) || "lazer room"
    name = name[0, MAX_MATCH_NAME_LEN] if name.size > MAX_MATCH_NAME_LEN

    Match.new(
      id: id,
      name: name,
      passwd: data["password"]?.try(&.as_s) || "",
      host_id: data["host_id"]?.try(&.as_i) || 0,
      map_id: data["map_id"]?.try(&.as_i) || 0,
      map_md5: data["map_md5"]?.try(&.as_s) || "",
      map_name: data["map_name"]?.try(&.as_s) || "",
      mods: Mods::NOMOD,
      mode: mode_of(data),
      win_condition: MatchWinConditions.new(0),
      team_type: MatchTeamTypes.new(0),
      freemods: true,
      seed: 0,
      chat: Channels.new(
        name: "#lazer_#{room_id}",
        topic: "Lazer room #{room_id}'s multiplayer channel.",
        auto_join: false,
        instance: true
      )
    )
  end

  # Update the fields a projection carries that a stable client renders.
  private def apply(match : Match, data : JSON::Any) : Nil
    if name = data["name"]?.try(&.as_s)
      match.name = name.size > MAX_MATCH_NAME_LEN ? name[0, MAX_MATCH_NAME_LEN] : name
    end

    # Host is projected too: MPv1 has no reconcile-on-connect, so if a host
    # transfer on the lazer side were not applied here the stable lobby would
    # keep showing the old one until the room closed.
    if host_id = data["host_id"]?.try(&.as_i)
      match.host_id = host_id
    end

    if password = data["password"]?
      match.passwd = password.as_s? || ""
    end

    if map_id = data["map_id"]?.try(&.as_i)
      match.map_id = map_id
    end

    if map_md5 = data["map_md5"]?
      match.map_md5 = map_md5.as_s? || ""
    end

    if map_name = data["map_name"]?
      match.map_name = map_name.as_s? || ""
    end

    if in_progress = data["in_progress"]?.try(&.as_bool) || false
      # MPv2 starting is not the same as a stable `MatchStartPacket`: only the
      # latter sets slot status and sends `match_start`, so without this a stable
      # player in the room would sit in something that claims to be in progress
      # while their client never loads the map. `Match#start` only touches slots
      # that hold a real session, so the projected lazer occupants are untouched.
      was_in_progress = match.in_progress
      match.in_progress = in_progress

      if in_progress && !was_in_progress
        match.start
      end
    end

    seat(match, data)
  end

  # Mirror the projection's slot occupants onto the `Match`.
  #
  # A slot occupied by a stable player is left alone: that seat is a real session
  # and the projection knows nothing about it, so overwriting it would either
  # evict the player or leave a stale id behind when they leave.
  private def seat(match : Match, data : JSON::Any) : Nil
    slots = data["slots"]?.try(&.as_a?) || return

    slots.each_with_index do |entry, i|
      break if i >= MAX_SLOTS

      slot = match.slots[i]
      next if slot.player

      fields = entry.as_h? || next
      user_id = fields["user_id"]?.try(&.as_i) || 0

      if user_id == 0
        # Lazer player left. Only projected seats are cleared -- an Open slot
        # that a stable player has not taken stays Open, and a Locked one stays
        # Locked so the host's layout survives.
        if slot.remote_id != 0
          slot.reset(slot.status == SlotStatus::Locked ? SlotStatus::Locked : SlotStatus::Open)
        end
        next
      end

      slot.remote_id = user_id
      slot.status = fields["ready"]?.try(&.as_bool) ? SlotStatus::Ready : SlotStatus::NotReady
    end
  end

  # Ask speedforce to do something to the room that owns it.
  #
  # This side never mutates a projected `Match` to mean "the stable player did
  # this" -- it asks, and speedforce applies it and republishes. That keeps the
  # one-writer rule the projection was built on: bakenohana would otherwise be a
  # second writer on a room it does not own, with no ordering between the two.
  #
  # `username` and `slot` are sent because speedforce cannot derive them. It
  # builds a `RoomUser` from a SignalR connection, and a stable player has none;
  # it also picks the first free slot independently, which disagrees with the
  # seat this side already committed to once a stable and a lazer player are both
  # present.
  #
  # Best-effort by design: a redis failure means the stable player's action does
  # not reach MPv2, which is no worse than the action having no effect at all.
  def intent(action : String, match_id : Int32, player : Player, ready : Bool = false) : Nil
    room_id = @@lock.synchronize { @@projected.invert[match_id]? }
    return unless room_id

    payload = JSON.build do |json|
      json.object do
        json.field "action", action
        json.field "room_id", room_id
        json.field "user_id", player.id
        json.field "username", player.username
        json.field "ready", ready

        if slot = match_slot_index(player)
          json.field "slot", slot
        end
      end
    end

    RedisService.publish(INTENT_CHANNEL, payload)
    rlog "[mpv2] intent #{action} by #{player.username} for lazer room #{room_id}", Ansi::LBLUE
  rescue ex
    rlog "[mpv2] intent publish failed: #{ex.message}", Ansi::LRED
  end

  # `@@projected` is keyed by lazer room id, so a `Match` has to be looked up the
  # other way round to name the room it came from.
  private def match_slot_index(player : Player) : Int32?
    MatchSession.each do |m|
      next unless @@lock.synchronize { @@projected.invert[m.id]? }

      m.slots.each_with_index do |slot, i|
        return i if slot.player.same?(player)
      end
    end
    nil
  end

  private def mode_of(data : JSON::Any) : Gamemode
    # lazer ruleset ids are 0-3 and so are the vanilla `Gamemode` values, so the
    # id passes straight through. Clamped because `Gamemode.new` raises on an
    # out-of-range value and a bad projection must not kill the handler.
    ruleset = data["ruleset_id"]?.try(&.as_i) || 0
    return Gamemode::VN_OSU unless Gamemode.valid_gamemodes.includes?(Gamemode.new(ruleset.to_u8))
    Gamemode.new(ruleset.to_u8)
  rescue
    Gamemode::VN_OSU
  end

  # Stable only learns a match exists by asking for it (`JoinLobbyPacket` walks
  # `MatchSession`), so anything already sitting in the lobby has to be told
  # explicitly or a room created after they joined stays invisible to them.
  private def broadcast(match : Match) : Nil
    packet = Packets.new_match(match)
    PlayerSession.each do |player, _|
      player.enqueue(packet) if player.in_lobby
    end
  end
end
