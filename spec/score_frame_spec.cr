require "spec"
require "../src/shared/value_objects/score_frame"

describe ScoreFrame do
  describe "#initialize" do
    it "creates with default values" do
      frame = ScoreFrame.new

      frame.time.should eq 0
      frame.id.should eq 0
      frame.num300.should eq 0
      frame.num100.should eq 0
      frame.num50.should eq 0
      frame.num_geki.should eq 0
      frame.num_katu.should eq 0
      frame.num_miss.should eq 0
      frame.total_score.should eq 0
      frame.max_combo.should eq 0
      frame.current_combo.should eq 0
      frame.perfect.should be_false
      frame.current_hp.should eq 0
      frame.tag_byte.should eq 0
      frame.score_v2.should be_false
      frame.combo_portion.should be_nil
      frame.bonus_portion.should be_nil
    end

    it "creates with custom values" do
      frame = ScoreFrame.new(
        time: 1000,
        id: 42,
        num300: 100_u16,
        num100: 10_u16,
        num50: 5_u16,
        num_geki: 20_u16,
        num_katu: 8_u16,
        num_miss: 2_u16,
        total_score: 150000,
        max_combo: 120_u16,
        current_combo: 85_u16,
        perfect: false,
        current_hp: 200_u8,
        tag_byte: 1_u8,
        score_v2: true,
        combo_portion: 0.75,
        bonus_portion: 0.25
      )

      frame.time.should eq 1000
      frame.id.should eq 42
      frame.num300.should eq 100
      frame.num100.should eq 10
      frame.num50.should eq 5
      frame.num_geki.should eq 20
      frame.num_katu.should eq 8
      frame.num_miss.should eq 2
      frame.total_score.should eq 150000
      frame.max_combo.should eq 120
      frame.current_combo.should eq 85
      frame.perfect.should be_false
      frame.current_hp.should eq 200
      frame.tag_byte.should eq 1
      frame.score_v2.should be_true
      frame.combo_portion.should eq 0.75
      frame.bonus_portion.should eq 0.25
    end
  end

  describe "property mutation" do
    it "allows changing mutable properties" do
      frame = ScoreFrame.new

      frame.time = 5000
      frame.time.should eq 5000

      frame.num300 = 250_u16
      frame.num300.should eq 250

      frame.total_score = 500000
      frame.total_score.should eq 500000

      frame.perfect = true
      frame.perfect.should be_true

      frame.combo_portion = 0.8
      frame.combo_portion.should eq 0.8
    end
  end

  describe "edge cases" do
    it "handles max values for UInt16 fields" do
      frame = ScoreFrame.new(
        num300: UInt16::MAX,
        num100: UInt16::MAX,
        max_combo: UInt16::MAX
      )

      frame.num300.should eq 65535
      frame.num100.should eq 65535
      frame.max_combo.should eq 65535
    end

    it "handles max value for UInt8 fields" do
      frame = ScoreFrame.new(
        current_hp: UInt8::MAX,
        tag_byte: UInt8::MAX
      )

      frame.current_hp.should eq 255
      frame.tag_byte.should eq 255
    end

    it "handles perfect combo" do
      frame = ScoreFrame.new(
        num300: 500_u16,
        num_miss: 0_u16,
        max_combo: 500_u16,
        current_combo: 500_u16,
        perfect: true
      )

      frame.perfect.should be_true
      frame.num_miss.should eq 0
      frame.max_combo.should eq frame.current_combo
    end
  end
end
