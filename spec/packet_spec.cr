require "spec"
require "../src/transport/protocol/packets"

alias ServerPacket = Packets::ServerPacket

describe Packets do
  describe ".silence_end" do
    it "creates valid packet" do
      bytes = Packets.silence_end(5000)

      bytes[0].should eq (ServerPacket::SILENCE_END.value & 0xFF)
      bytes[1].should eq ((ServerPacket::SILENCE_END.value >> 8) & 0xFF)
      bytes.size.should be > 7
    end

    it "handles zero delta" do
      bytes = Packets.silence_end(0)
      bytes.size.should be > 0
    end
  end

  describe ".user_silenced" do
    it "creates valid packet" do
      bytes = Packets.user_silenced(12345)

      bytes[0].should eq (ServerPacket::USER_SILENCED.value & 0xFF)
      bytes[1].should eq ((ServerPacket::USER_SILENCED.value >> 8) & 0xFF)
    end
  end

  describe ".login_reply" do
    it "creates valid packet with positive user id" do
      bytes = Packets.login_reply(999)

      bytes[0].should eq (ServerPacket::USER_ID.value & 0xFF)
      bytes[1].should eq ((ServerPacket::USER_ID.value >> 8) & 0xFF)
    end

    it "handles negative user id for error codes" do
      bytes = Packets.login_reply(-1)
      bytes.size.should be > 0
    end
  end

  describe ".pong" do
    it "creates valid empty packet" do
      bytes = Packets.pong

      bytes[0].should eq (ServerPacket::PONG.value & 0xFF)
      bytes[1].should eq ((ServerPacket::PONG.value >> 8) & 0xFF)
      bytes[3..6].should eq Bytes[0x00, 0x00, 0x00, 0x00]
    end
  end

  describe ".protocol_version" do
    it "creates valid packet" do
      bytes = Packets.protocol_version(19)

      bytes[0].should eq (ServerPacket::PROTOCOL_VERSION.value & 0xFF)
      bytes[1].should eq ((ServerPacket::PROTOCOL_VERSION.value >> 8) & 0xFF)
    end
  end

  describe ".bancho_privileges" do
    it "creates valid packet" do
      bytes = Packets.bancho_privileges(31)

      bytes[0].should eq (ServerPacket::PRIVILEGES.value & 0xFF)
      bytes[1].should eq ((ServerPacket::PRIVILEGES.value >> 8) & 0xFF)
    end
  end

  describe ".notification" do
    it "creates valid packet with message" do
      bytes = Packets.notification("Welcome to the server!")

      bytes[0].should eq (ServerPacket::NOTIFICATION.value & 0xFF)
      bytes[1].should eq ((ServerPacket::NOTIFICATION.value >> 8) & 0xFF)
      String.new(bytes[9..]).should eq "Welcome to the server!"
    end

    it "handles empty notification" do
      bytes = Packets.notification("")
      bytes.size.should be > 0
    end

    it "handles long notification" do
      long_msg = "a" * 500
      bytes = Packets.notification(long_msg)
      bytes.size.should be > 500
    end
  end

  describe ".send_message" do
    it "creates valid packet" do
      bytes = Packets.send_message("player1", "hello world", "#osu", 100)

      bytes[0].should eq (ServerPacket::SEND_MESSAGE.value & 0xFF)
      bytes[1].should eq ((ServerPacket::SEND_MESSAGE.value >> 8) & 0xFF)
      bytes.size.should be > 20
    end

    it "handles private message" do
      bytes = Packets.send_message("admin", "restricted", "cheater", 1)
      bytes.size.should be > 0
    end
  end

  describe ".logout" do
    it "creates valid packet" do
      bytes = Packets.logout(42)

      bytes[0].should eq (ServerPacket::USER_LOGOUT.value & 0xFF)
      bytes[1].should eq ((ServerPacket::USER_LOGOUT.value >> 8) & 0xFF)
    end
  end

  describe ".account_restricted" do
    it "creates valid empty packet" do
      bytes = Packets.account_restricted

      bytes[0].should eq (ServerPacket::ACCOUNT_RESTRICTED.value & 0xFF)
      bytes[1].should eq ((ServerPacket::ACCOUNT_RESTRICTED.value >> 8) & 0xFF)
      bytes[3..6].should eq Bytes[0x00, 0x00, 0x00, 0x00]
    end
  end

  describe ".channel_info_end" do
    it "creates valid empty packet" do
      bytes = Packets.channel_info_end

      bytes[0].should eq (ServerPacket::CHANNEL_INFO_END.value & 0xFF)
      bytes[1].should eq ((ServerPacket::CHANNEL_INFO_END.value >> 8) & 0xFF)
      bytes[3..6].should eq Bytes[0x00, 0x00, 0x00, 0x00]
    end
  end

  describe ".channel_info" do
    it "creates valid packet" do
      bytes = Packets.channel_info("#osu", "General discussion", 150)

      bytes[0].should eq (ServerPacket::CHANNEL_INFO.value & 0xFF)
      bytes[1].should eq ((ServerPacket::CHANNEL_INFO.value >> 8) & 0xFF)
      bytes.size.should be > 20
    end

    it "handles empty topic" do
      bytes = Packets.channel_info("#test", "", 0)
      bytes.size.should be > 0
    end
  end

  describe ".channel_join" do
    it "creates valid packet" do
      bytes = Packets.channel_join("#osu")

      bytes[0].should eq (ServerPacket::CHANNEL_JOIN.value & 0xFF)
      bytes[1].should eq ((ServerPacket::CHANNEL_JOIN.value >> 8) & 0xFF)
      String.new(bytes[9..]).should eq "#osu"
    end

    it "handles spectator channel" do
      bytes = Packets.channel_join("#spec_12345")
      String.new(bytes[9..]).should eq "#spec_12345"
    end
  end

  describe ".channel_kick" do
    it "creates valid packet" do
      bytes = Packets.channel_kick("#spectator")

      bytes[0].should eq (ServerPacket::CHANNEL_KICK.value & 0xFF)
      bytes[1].should eq ((ServerPacket::CHANNEL_KICK.value >> 8) & 0xFF)
      String.new(bytes[9..]).should eq "#spectator"
    end
  end

  describe ".spectator_joined" do
    it "creates valid packet" do
      bytes = Packets.spectator_joined(12345)

      bytes[0].should eq (ServerPacket::SPECTATOR_JOINED.value & 0xFF)
      bytes[1].should eq ((ServerPacket::SPECTATOR_JOINED.value >> 8) & 0xFF)
    end
  end

  describe ".spectator_left" do
    it "creates valid packet" do
      bytes = Packets.spectator_left(12345)

      bytes[0].should eq (ServerPacket::SPECTATOR_LEFT.value & 0xFF)
      bytes[1].should eq ((ServerPacket::SPECTATOR_LEFT.value >> 8) & 0xFF)
    end
  end

  describe ".spectator_cant_spectate" do
    it "creates valid packet" do
      bytes = Packets.spectator_cant_spectate(0)

      bytes[0].should eq (ServerPacket::SPECTATOR_CANT_SPECTATE.value & 0xFF)
      bytes[1].should eq ((ServerPacket::SPECTATOR_CANT_SPECTATE.value >> 8) & 0xFF)
      bytes[3..6].should eq Bytes[0x04, 0x00, 0x00, 0x00]
    end
  end

  describe ".f_spectator_joined" do
    it "creates valid packet" do
      bytes = Packets.f_spectator_joined(99999)

      bytes[0].should eq (ServerPacket::FELLOW_SPECTATOR_JOINED.value & 0xFF)
      bytes[1].should eq ((ServerPacket::FELLOW_SPECTATOR_JOINED.value >> 8) & 0xFF)
    end
  end

  describe ".f_spectator_left" do
    it "creates valid packet" do
      bytes = Packets.f_spectator_left(99999)

      bytes[0].should eq (ServerPacket::FELLOW_SPECTATOR_LEFT.value & 0xFF)
      bytes[1].should eq ((ServerPacket::FELLOW_SPECTATOR_LEFT.value >> 8) & 0xFF)
    end
  end

  describe ".spectator_frames" do
    it "creates valid packet with frame data" do
      frame_data = Bytes[0x01, 0x02, 0x03, 0x04]
      bytes = Packets.spectator_frames(frame_data)

      bytes[0].should eq (ServerPacket::SPECTATE_FRAMES.value & 0xFF)
      bytes[1].should eq ((ServerPacket::SPECTATE_FRAMES.value >> 8) & 0xFF)
      bytes[-4..].should eq frame_data
    end
  end

  describe ".restart_server" do
    it "creates valid packet" do
      bytes = Packets.restart_server(30000)

      bytes[0].should eq (ServerPacket::RESTART.value & 0xFF)
      bytes[1].should eq ((ServerPacket::RESTART.value >> 8) & 0xFF)
    end
  end

  describe ".friends_list" do
    it "creates valid packet with friend ids" do
      friends = [10, 20, 30, 40, 50]
      bytes = Packets.friends_list(friends)

      bytes[0].should eq (ServerPacket::FRIENDS_LIST.value & 0xFF)
      bytes[1].should eq ((ServerPacket::FRIENDS_LIST.value >> 8) & 0xFF)

      list_size = bytes[7].to_u16 | (bytes[8].to_u16 << 8)
      list_size.should eq 5
    end

    it "handles empty friends list" do
      bytes = Packets.friends_list([] of Int32)

      bytes[7..8].should eq Bytes[0x00, 0x00]
    end
  end

  describe ".dispose_match" do
    it "creates valid packet" do
      bytes = Packets.dispose_match(42)

      bytes[0].should eq (ServerPacket::DISPOSE_MATCH.value & 0xFF)
      bytes[1].should eq ((ServerPacket::DISPOSE_MATCH.value >> 8) & 0xFF)
    end
  end

  describe ".user_dm_blocked" do
    it "creates valid packet" do
      bytes = Packets.user_dm_blocked("player")

      bytes[0].should eq (ServerPacket::USER_DM_BLOCKED.value & 0xFF)
      bytes[1].should eq ((ServerPacket::USER_DM_BLOCKED.value >> 8) & 0xFF)
    end
  end

  describe ".target_is_silenced" do
    it "creates valid packet" do
      bytes = Packets.target_is_silenced("player")

      bytes[0].should eq (ServerPacket::TARGET_IS_SILENCED.value & 0xFF)
      bytes[1].should eq ((ServerPacket::TARGET_IS_SILENCED.value >> 8) & 0xFF)
    end
  end
end
