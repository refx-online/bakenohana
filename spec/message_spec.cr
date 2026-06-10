require "spec"
require "../src/shared/value_objects/message"

describe Message do
  describe "initialization" do
    it "creates message with all fields" do
      msg = Message.new(
        sender: "player1",
        text: "hello world",
        recipient: "player2",
        sender_id: 42
      )

      msg.sender.should eq "player1"
      msg.text.should eq "hello world"
      msg.recipient.should eq "player2"
      msg.sender_id.should eq 42
    end

    it "creates channel message" do
      msg = Message.new(
        sender: "moderator",
        text: "welcome to #osu",
        recipient: "#osu",
        sender_id: 1
      )

      msg.sender.should eq "moderator"
      msg.text.should eq "welcome to #osu"
      msg.recipient.should eq "#osu"
      msg.sender_id.should eq 1
    end

    it "creates private message" do
      msg = Message.new(
        sender: "admin",
        text: "you have been restricted",
        recipient: "cheater",
        sender_id: 1
      )

      msg.sender.should eq "admin"
      msg.text.should eq "you have been restricted"
      msg.recipient.should eq "cheater"
      msg.sender_id.should eq 1
    end

    it "handles empty text" do
      msg = Message.new(
        sender: "user",
        text: "",
        recipient: "#chat",
        sender_id: 10
      )

      msg.text.should eq ""
    end

    it "handles long text" do
      long_text = "a" * 1000
      msg = Message.new(
        sender: "spammer",
        text: long_text,
        recipient: "#osu",
        sender_id: 99
      )

      msg.text.should eq long_text
      msg.text.size.should eq 1000
    end
  end
end
