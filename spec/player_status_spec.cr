require "spec"
require "../src/domain/player/status"

describe PlayerStatus do
  describe "initialization" do
    it "creates with default values" do
      status = PlayerStatus.new

      status.action.should eq 0
      status.info_text.should eq ""
      status.map_md5.should eq ""
      status.map_id.should eq 0
      status.mods.should eq Mods::NOMOD
      status.mode.should eq Gamemode::VN_OSU
      status.latitude.should eq 0
      status.longitude.should eq 0
      status.country_code.should eq 0
      status.country.should eq ""
      status.utc_offset.should eq 0
    end
  end

  describe "property mutation" do
    it "allows setting action and info" do
      status = PlayerStatus.new
      status.action = 2_u8
      status.info_text = "Playing osu!"

      status.action.should eq 2
      status.info_text.should eq "Playing osu!"
    end

    it "allows setting beatmap info" do
      status = PlayerStatus.new
      status.map_md5 = "abc123def456"
      status.map_id = 123456

      status.map_md5.should eq "abc123def456"
      status.map_id.should eq 123456
    end

    it "allows setting mods" do
      status = PlayerStatus.new
      status.mods = Mods::HIDDEN | Mods::DOUBLETIME

      status.mods.should eq (Mods::HIDDEN | Mods::DOUBLETIME)
    end

    it "allows setting mode" do
      status = PlayerStatus.new
      status.mode = Gamemode::VN_TAIKO

      status.mode.should eq Gamemode::VN_TAIKO
    end

    it "allows setting location" do
      status = PlayerStatus.new
      status.latitude = 35.6762_f32
      status.longitude = 139.6503_f32
      status.country_code = 111
      status.country = "jp"

      status.latitude.should eq 35.6762_f32
      status.longitude.should eq 139.6503_f32
      status.country_code.should eq 111
      status.country.should eq "jp"
    end

    it "allows setting UTC offset" do
      status = PlayerStatus.new
      status.utc_offset = 9

      status.utc_offset.should eq 9
    end
  end

  describe "realistic status scenarios" do
    it "represents idle player" do
      status = PlayerStatus.new
      status.action = 0_u8
      status.info_text = ""

      status.action.should eq 0
      status.info_text.should be_empty
    end

    it "represents player in lobby" do
      status = PlayerStatus.new
      status.action = 4_u8
      status.info_text = "In lobby"

      status.action.should eq 4
      status.info_text.should eq "In lobby"
    end

    it "represents player playing" do
      status = PlayerStatus.new
      status.action = 2_u8
      status.info_text = "xi - Blue Zenith [FOUR DIMENSIONS]"
      status.map_md5 = "abc123"
      status.map_id = 658127
      status.mods = Mods::HIDDEN | Mods::DOUBLETIME
      status.mode = Gamemode::VN_OSU

      status.action.should eq 2
      status.map_id.should eq 658127
      status.mods.value.should eq (8 | 64)
    end

    it "represents player spectating" do
      status = PlayerStatus.new
      status.action = 6_u8
      status.info_text = "Watching someone"

      status.action.should eq 6
    end

    it "represents player editing" do
      status = PlayerStatus.new
      status.action = 3_u8
      status.info_text = "Editing beatmap"

      status.action.should eq 3
    end
  end
end
