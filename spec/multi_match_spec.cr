require "spec"
require "../src/shared/value_objects/multi_match"

describe MultiMatch do
  describe "#initialize" do
    it "creates with default values" do
      match = MultiMatch.new

      match.id.should eq 0
      match.in_progress.should be_false
      match.powerplay.should eq 0
      match.mods.should eq 0
      match.name.should eq ""
      match.passwd.should eq ""
      match.map_name.should eq ""
      match.map_id.should eq 0
      match.map_md5.should eq ""
      match.slot_statuses.size.should eq 16
      match.slot_teams.size.should eq 16
      match.slot_ids.should be_empty
      match.host_id.should eq 0
      match.mode.should eq 0
      match.win_condition.should eq 0
      match.team_type.should eq 0
      match.freemods.should be_false
      match.slot_mods.size.should eq 16
      match.seed.should eq 0
    end

    it "initializes slot arrays correctly" do
      match = MultiMatch.new

      match.slot_statuses.each { |s| s.should eq 0 }
      match.slot_teams.each { |t| t.should eq 0 }
      match.slot_mods.each { |m| m.should eq 0 }
    end
  end

  describe "property mutation" do
    it "allows setting match metadata" do
      match = MultiMatch.new

      match.id = 42_i16
      match.name = "Tournament Finals"
      match.passwd = "secret123"
      match.in_progress = true

      match.id.should eq 42
      match.name.should eq "Tournament Finals"
      match.passwd.should eq "secret123"
      match.in_progress.should be_true
    end

    it "allows setting beatmap data" do
      match = MultiMatch.new

      match.map_name = "Halozy - Genryuu Kaiko"
      match.map_id = 123456
      match.map_md5 = "a1b2c3d4e5f6"

      match.map_name.should eq "Halozy - Genryuu Kaiko"
      match.map_id.should eq 123456
      match.map_md5.should eq "a1b2c3d4e5f6"
    end

    it "allows setting game settings" do
      match = MultiMatch.new

      match.mode = 0_i8
      match.win_condition = 2_i8
      match.team_type = 1_i8
      match.freemods = true
      match.mods = 64 # DT

      match.mode.should eq 0
      match.win_condition.should eq 2
      match.team_type.should eq 1
      match.freemods.should be_true
      match.mods.should eq 64
    end

    it "allows setting host" do
      match = MultiMatch.new

      match.host_id = 12345

      match.host_id.should eq 12345
    end

    it "allows modifying slot arrays" do
      match = MultiMatch.new

      match.slot_statuses[0] = 4_i8 # ready
      match.slot_teams[0] = 1_i8    # red
      match.slot_mods[0] = 64       # DT

      match.slot_statuses[0].should eq 4
      match.slot_teams[0].should eq 1
      match.slot_mods[0].should eq 64
    end

    it "allows setting slot player IDs" do
      match = MultiMatch.new

      match.slot_ids = [100, 200, 300, 400]

      match.slot_ids.size.should eq 4
      match.slot_ids[0].should eq 100
      match.slot_ids[3].should eq 400
    end

    it "allows setting seed for multiplayer score" do
      match = MultiMatch.new

      match.seed = 987654321

      match.seed.should eq 987654321
    end
  end

  describe "realistic match scenarios" do
    it "creates head-to-head match" do
      match = MultiMatch.new
      match.id = 1_i16
      match.name = "1v1 tournament"
      match.mode = 0_i8
      match.win_condition = 0_i8
      match.team_type = 0_i8
      match.host_id = 100
      match.slot_statuses[0] = 4_i8
      match.slot_statuses[1] = 4_i8
      match.slot_ids = [100, 200]

      match.team_type.should eq 0
      match.slot_ids.size.should eq 2
    end

    it "creates team vs match" do
      match = MultiMatch.new
      match.id = 5_i16
      match.name = "Red vs Blue"
      match.team_type = 1_i8
      match.slot_teams[0] = 1_i8 # red
      match.slot_teams[1] = 1_i8 # red
      match.slot_teams[2] = 2_i8 # blue
      match.slot_teams[3] = 2_i8 # blue

      match.team_type.should eq 1
      match.slot_teams[0].should eq 1
      match.slot_teams[2].should eq 2
    end

    it "creates tag coop match" do
      match = MultiMatch.new
      match.id = 10_i16
      match.name = "Coop Play"
      match.team_type = 2_i8
      match.mode = 0_i8

      match.team_type.should eq 2
    end

    it "creates tag team vs match" do
      match = MultiMatch.new
      match.id = 15_i16
      match.name = "Tag Team Battle"
      match.team_type = 3_i8

      match.team_type.should eq 3
    end

    it "creates freemods match" do
      match = MultiMatch.new
      match.name = "Freemod Lobby"
      match.freemods = true
      match.mods = 0
      match.slot_mods[0] = 64  # player 0: DT
      match.slot_mods[1] = 256 # player 1: HD

      match.freemods.should be_true
      match.slot_mods[0].should eq 64
      match.slot_mods[1].should eq 256
    end

    it "creates password-protected match" do
      match = MultiMatch.new
      match.name = "Private Tournament"
      match.passwd = "tourney2024"

      match.passwd.should_not be_empty
      match.passwd.should eq "tourney2024"
    end

    it "tracks in-progress state" do
      match = MultiMatch.new
      match.in_progress = false

      match.in_progress.should be_false

      match.in_progress = true
      match.in_progress.should be_true
    end
  end
end
