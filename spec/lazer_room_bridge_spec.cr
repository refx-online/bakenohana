require "spec"
require "json"
require "../src/domain/match/lazer_room_bridge"
require "../src/state/match_session"
require "../src/transport/protocol/packets"
require "../src/domain/match/match"

ROOM_ID = 4242

# Built with `JSON.build` rather than a hand-written literal: the payload is full
# of `{`/`}`, and Crystal's `%()` literal pairs those with the closing delimiter,
# which silently truncates the JSON. A malformed payload is a no-op here, so the
# failure surfaces as "match not found" rather than as a parse error.
def room_json(
  room_id : Int32 = ROOM_ID,
  closed : Bool = false,
  name : String? = nil,
  host_id : Int32? = nil,
  map_id : Int32? = nil,
  slots : Array({Int32, Bool})? = nil,
  in_progress : Bool? = nil
) : String
  JSON.build do |json|
    json.object do
      json.field "room_id", room_id
      json.field "closed", closed
      json.field "name", name if name
      json.field "host_id", host_id if host_id
      json.field "map_id", map_id if map_id
      json.field "in_progress", in_progress unless in_progress.nil?
      if slots
        json.field "slots" do
          json.array do
            # Padded to 16 because that is what the publisher sends
            # (bridge.py `MAX_SLOTS`); a shorter array leaves the tail alone.
            occupied = slots.to_a
            16.times do |i|
              entry = i < occupied.size ? occupied[i] : {0, false}
              json.object do
                json.field "user_id", entry[0]
                json.field "ready", entry[1]
              end
            end
          end
        end
      end
    end
  end
end

def project(json : String) : Nil
  LazerRoomBridge.handle(json)
end

def find_match_by_name(name : String) : Match
  found = nil
  MatchSession.each { |match| found = match if match.name == name }
  raise "no projected match named #{name.inspect}" unless found
  found
end

# `Player` wants a token, ip, login time and privileges; none of them matter
# here, and registering the session in `PlayerSession` would leak it into every
# broadcast these tests trigger.
def test_player(id : Int32, username : String) : Player
  Player.new(id, username, "token#{id}", "127.0.0.1", Time.utc, Privileges::UNRESTRICTED)
end

# Byte-wise search: `Bytes#to_s` builds a String from arbitrary binary, so a
# substring check on it is not a byte comparison.
def contains?(haystack : Bytes, needle : Bytes) : Bool
  (0..(haystack.size - needle.size)).any? { |i| haystack[i, needle.size] == needle }
end

describe LazerRoomBridge do
  after_each do
    project(room_json(closed: true))
  end

  it "seats lazer players so a projected room is not hostless or empty" do
    project(room_json(name: "crossplay", host_id: 42, map_id: 1, slots: [{42, true}, {43, false}]))

    match = find_match_by_name("crossplay")

    match.host_id.should eq 42
    match.slots[0].remote_id.should eq 42
    match.slots[0].status.should eq SlotStatus::Ready
    match.slots[0].user_id.should eq 42
    match.slots[1].remote_id.should eq 43
    match.slots[1].status.should eq SlotStatus::NotReady
    match.slots[2].should be_empty

    # `host_user_id` is what packet_writer writes, and it resolves through the
    # slot -- so this is the assertion that a stable client sees a host at all.
    match.host_user_id.should eq 42
    contains?(Packets.new_match(match), Bytes[42, 0, 0, 0]).should be_true
  end

  it "tells a seated stable client when a projected seat changes" do
    project(room_json(name: "crossplay", host_id: 42, slots: [{42, true}]))
    match = find_match_by_name("crossplay")

    # A stable player already seated in the match. Deliberately not registered
    # in `PlayerSession`, so `broadcast`'s lobby fan-out cannot reach it: the
    # only thing that can land in its queue is the match-channel state push,
    # which is exactly the path that was missing.
    watcher = test_player(7, "stable7")
    match.chat.append(watcher)

    project(room_json(name: "crossplay", host_id: 42, slots: [{42, true}, {43, false}]))

    bytes = watcher.dequeue
    bytes.size.should be > 7
    bytes[0].should eq (Packets::ServerPacket::UPDATE_MATCH.value & 0xFF)
    bytes[1].should eq ((Packets::ServerPacket::UPDATE_MATCH.value >> 8) & 0xFF)
  end

  it "clears a seat when its lazer player leaves" do
    project(room_json(host_id: 42, slots: [{42, true}]))
    find_match_by_name("lazer room").slots[0].remote_id.should eq 42

    project(room_json(host_id: 42, slots: [{42, true}, {43, false}]))
    find_match_by_name("lazer room").slots[1].remote_id.should eq 43

    project(room_json(host_id: 42, slots: [{42, true}]))
    match = find_match_by_name("lazer room")
    match.slots[1].remote_id.should eq 0
    match.slots[1].should be_empty
  end

  it "updates a seat in place instead of rebuilding the match" do
    project(room_json(name: "crossplay", host_id: 42, slots: [{42, true}]))
    project(room_json(name: "crossplay", host_id: 43, slots: [{43, true}]))

    match = find_match_by_name("crossplay")
    match.id.should eq 0
    match.host_id.should eq 43
    match.host_user_id.should eq 43
    match.slots[0].remote_id.should eq 43
    match.slots[0].status.should eq SlotStatus::Ready
  end

  it "survives a malformed payload" do
    project(room_json(host_id: 42, slots: [{42, true}]))
    project("not json at all")
    project(room_json(host_id: 42, slots: [{42, true}]))
    find_match_by_name("lazer room").slots[0].remote_id.should eq 42
  end

  it "keeps slots when a projection omits them" do
    project(room_json(host_id: 42, slots: [{42, true}]))
    project(room_json(name: "renamed"))

    match = find_match_by_name("renamed")
    match.slots[0].remote_id.should eq 42
  end

  it "disposes a projected match when the lazer room closes" do
    project(room_json(name: "crossplay", host_id: 42))
    MatchSession.count.should eq 1

    project(room_json(closed: true))
    MatchSession.count.should eq 0
  end

  it "marks a projected match so it is not mistaken for a locally created one" do
    project(room_json(name: "crossplay", host_id: 42))
    find_match_by_name("crossplay").projected.should be_true
  end

  it "starts stable players when MPv2 starts the game" do
    project(room_json(name: "crossplay", host_id: 42, slots: [{42, true}]))
    match = find_match_by_name("crossplay")
    match.in_progress.should be_false

    # The stable player is seated as a real session; a lazer-only room would not
    # make this observable.
    player = test_player(7, "stable7")
    index = match.get_free.not_nil!
    match.slots[index].player = player
    match.slots[index].status = SlotStatus::NotReady

    project(room_json(name: "crossplay", host_id: 42, slots: [{42, true}], in_progress: true))

    match.in_progress.should be_true
    match.slots[index].status.should eq SlotStatus::Playing
    # A projected lazer occupant has no session, so `Match#start` leaves it alone.
    match.slots[0].status.should eq SlotStatus::Ready
  end

  it "does not re-send match_start on every projection once in progress" do
    project(room_json(name: "crossplay", host_id: 42, in_progress: true))
    match = find_match_by_name("crossplay")

    # Back to idle, then in again: the second transition must start again, while
    # a repeat of the same state must not re-enter `start`.
    project(room_json(name: "crossplay", host_id: 42, in_progress: false))
    match.in_progress.should be_false

    player = test_player(8, "stable8")
    index = match.get_free.not_nil!
    match.slots[index].player = player

    project(room_json(name: "crossplay", host_id: 42, in_progress: true))
    match.slots[index].status.should eq SlotStatus::Playing
  end

  it "keeps a projected room alive when a stable player leaves and it empties" do
    project(room_json(name: "crossplay", host_id: 42))
    match = find_match_by_name("crossplay")

    player = test_player(9, "stable9")
    index = match.get_free.not_nil!
    match.slots[index].player = player
    player.match = match

    player.leave_match

    # The room is speedforce's to retract. Disposing here would make it vanish
    # from every stable client until the next publish.
    MatchSession.count.should eq 1
    match.slots[index].should be_empty
  end
end
