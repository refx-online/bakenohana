require "spec"
require "../src/domain/player/stats"

describe PlayerStats do
  describe "initialization" do
    it "creates with default values" do
      stats = PlayerStats.new

      stats.pp.should eq 0
      stats.acc.should eq 100.0
      stats.global_rank.should eq 0
      stats.country_rank.should eq 0
      stats.plays.should eq 0
      stats.tscore.should eq 0
      stats.rscore.should eq 0
      stats.total_hits.should eq 0
      stats.max_combo.should eq 0
      stats.xh.should eq 0
      stats.x.should eq 0
      stats.sh.should eq 0
      stats.s.should eq 0
      stats.a.should eq 0
    end
  end

  describe "property mutation" do
    it "allows setting pp" do
      stats = PlayerStats.new
      stats.pp = 5000
      stats.pp.should eq 5000
    end

    it "allows setting accuracy" do
      stats = PlayerStats.new
      stats.acc = 98.75
      stats.acc.should eq 98.75
    end

    it "allows setting ranks" do
      stats = PlayerStats.new
      stats.global_rank = 100
      stats.country_rank = 10
      stats.global_rank.should eq 100
      stats.country_rank.should eq 10
    end

    it "allows setting play count" do
      stats = PlayerStats.new
      stats.plays = 5000
      stats.plays.should eq 5000
    end

    it "allows setting scores" do
      stats = PlayerStats.new
      stats.tscore = 1_000_000_000_i64
      stats.rscore = 500_000_000_i64
      stats.tscore.should eq 1_000_000_000
      stats.rscore.should eq 500_000_000
    end

    it "allows setting hit stats" do
      stats = PlayerStats.new
      stats.total_hits = 100_000
      stats.max_combo = 1500
      stats.total_hits.should eq 100_000
      stats.max_combo.should eq 1500
    end

    it "allows setting grade counts" do
      stats = PlayerStats.new
      stats.xh = 10
      stats.x = 20
      stats.sh = 30
      stats.s = 40
      stats.a = 50

      stats.xh.should eq 10
      stats.x.should eq 20
      stats.sh.should eq 30
      stats.s.should eq 40
      stats.a.should eq 50
    end
  end

  describe "realistic player scenarios" do
    it "represents new player stats" do
      stats = PlayerStats.new
      stats.pp = 0
      stats.acc = 100.0
      stats.plays = 0
      stats.global_rank = 0

      stats.pp.should eq 0
      stats.plays.should eq 0
    end

    it "represents average player stats" do
      stats = PlayerStats.new
      stats.pp = 3500
      stats.acc = 96.5
      stats.plays = 10_000
      stats.global_rank = 50_000
      stats.country_rank = 5_000

      stats.pp.should eq 3500
      stats.acc.should eq 96.5
    end

    it "represents top player stats" do
      stats = PlayerStats.new
      stats.pp = 15_000
      stats.acc = 99.5
      stats.plays = 100_000
      stats.global_rank = 10
      stats.country_rank = 1
      stats.xh = 500
      stats.x = 1000

      stats.global_rank.should eq 10
      stats.country_rank.should eq 1
    end

    it "handles max pp values" do
      stats = PlayerStats.new
      stats.pp = Int32::MAX
      stats.pp.should eq 2_147_483_647
    end

    it "handles large score values" do
      stats = PlayerStats.new
      stats.tscore = 9_999_999_999_999_i64
      stats.rscore = 8_888_888_888_888_i64

      stats.tscore.should eq 9_999_999_999_999
      stats.rscore.should eq 8_888_888_888_888
    end
  end
end
