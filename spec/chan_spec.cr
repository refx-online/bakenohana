require "spec"
require "../src/shared/value_objects/channel"

describe Chan do
  describe "initialization" do
    it "creates public channel" do
      chan = Chan.new(
        name: "#osu",
        topic: "General discussion",
        players: 150
      )

      chan.name.should eq "#osu"
      chan.topic.should eq "General discussion"
      chan.players.should eq 150
    end

    it "creates announce channel" do
      chan = Chan.new(
        name: "#announce",
        topic: "Server announcements",
        players: 500
      )

      chan.name.should eq "#announce"
      chan.topic.should eq "Server announcements"
      chan.players.should eq 500
    end

    it "creates empty channel" do
      chan = Chan.new(
        name: "#empty",
        topic: "No one here",
        players: 0
      )

      chan.name.should eq "#empty"
      chan.topic.should eq "No one here"
      chan.players.should eq 0
    end

    it "creates spectator instance channel" do
      chan = Chan.new(
        name: "#spec_12345",
        topic: "",
        players: 2
      )

      chan.name.should eq "#spec_12345"
      chan.topic.should eq ""
      chan.players.should eq 2
    end

    it "creates multiplayer instance channel" do
      chan = Chan.new(
        name: "#multi_42",
        topic: "Tournament Match",
        players: 16
      )

      chan.name.should eq "#multi_42"
      chan.topic.should eq "Tournament Match"
      chan.players.should eq 16
    end
  end
end
