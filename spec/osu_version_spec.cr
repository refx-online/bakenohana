require "spec"
require "../src/shared/value_objects/osu_version"

describe OsuVersion do
  describe ".parse" do
    it "parses vanilla stable version" do
      version = OsuVersion.parse("b20240515")
      version.should_not be_nil
      version = version.not_nil!

      version.date.should eq "20240515"
      version.revision.should be_nil
      version.stream.should eq "stable"
      version.is_refx.should be_false
    end

    it "parses vanilla stable with revision" do
      version = OsuVersion.parse("b20240515.2")
      version.should_not be_nil
      version = version.not_nil!

      version.date.should eq "20240515"
      version.revision.should eq 2
      version.stream.should eq "stable"
      version.is_refx.should be_false
    end

    it "parses vanilla beta stream" do
      version = OsuVersion.parse("b20240515beta")
      version.should_not be_nil
      version = version.not_nil!

      version.date.should eq "20240515"
      version.stream.should eq "beta"
      version.is_refx.should be_false
    end

    it "parses vanilla cuttingedge stream" do
      version = OsuVersion.parse("b20240515cuttingedge")
      version.should_not be_nil
      version = version.not_nil!

      version.date.should eq "20240515"
      version.stream.should eq "cuttingedge"
      version.is_refx.should be_false
    end

    it "parses vanilla tourney stream" do
      version = OsuVersion.parse("b20240515tourney")
      version.should_not be_nil
      version = version.not_nil!

      version.date.should eq "20240515"
      version.stream.should eq "tourney"
      version.is_refx.should be_false
    end

    it "parses vanilla dev stream" do
      version = OsuVersion.parse("b20240515dev")
      version.should_not be_nil
      version = version.not_nil!

      version.date.should eq "20240515"
      version.stream.should eq "dev"
      version.is_refx.should be_false
    end

    it "parses refx stable version" do
      version = OsuVersion.parse("Re;fx b20240515")
      version.should_not be_nil
      version = version.not_nil!

      version.date.should eq "20240515"
      version.revision.should be_nil
      version.stream.should eq "stable"
      version.is_refx.should be_true
    end

    it "parses refx stable with revision" do
      version = OsuVersion.parse("Re;fx b20240515.3")
      version.should_not be_nil
      version = version.not_nil!

      version.date.should eq "20240515"
      version.revision.should eq 3
      version.stream.should eq "stable"
      version.is_refx.should be_true
    end

    it "parses refx beta stream" do
      version = OsuVersion.parse("Re;fx b20240515beta")
      version.should_not be_nil
      version = version.not_nil!

      version.date.should eq "20240515"
      version.stream.should eq "beta"
      version.is_refx.should be_true
    end

    it "returns nil for invalid version string" do
      OsuVersion.parse("invalid").should be_nil
      OsuVersion.parse("").should be_nil
      OsuVersion.parse("b2024").should be_nil
      OsuVersion.parse("20240515").should be_nil
    end
  end

  describe "#year" do
    it "extracts year from date" do
      version = OsuVersion.new("20240515", nil, "stable")
      version.year.should eq 2024

      version = OsuVersion.new("20191225", nil, "stable")
      version.year.should eq 2019

      version = OsuVersion.new("20260101", nil, "stable")
      version.year.should eq 2026
    end
  end

  describe "#to_s" do
    it "formats vanilla stable without revision" do
      version = OsuVersion.new("20240515", nil, "stable", false)
      version.to_s.should eq "b20240515"
    end

    it "formats vanilla stable with revision" do
      version = OsuVersion.new("20240515", 2, "stable", false)
      version.to_s.should eq "b20240515.2"
    end

    it "formats vanilla non-stable stream" do
      version = OsuVersion.new("20240515", nil, "beta", false)
      version.to_s.should eq "b20240515beta"

      version = OsuVersion.new("20240515", nil, "cuttingedge", false)
      version.to_s.should eq "b20240515cuttingedge"
    end

    it "formats refx stable without revision" do
      version = OsuVersion.new("20240515", nil, "stable", true)
      version.to_s.should eq "Re;fx b20240515"
    end

    it "formats refx stable with revision" do
      version = OsuVersion.new("20240515", 3, "stable", true)
      version.to_s.should eq "Re;fx b20240515.3"
    end

    it "formats refx non-stable stream" do
      version = OsuVersion.new("20240515", nil, "beta", true)
      version.to_s.should eq "Re;fx b20240515beta"
    end

    it "formats refx with revision and stream" do
      version = OsuVersion.new("20240515", 5, "cuttingedge", true)
      version.to_s.should eq "Re;fx b20240515.5cuttingedge"
    end
  end

  describe "round-trip parsing" do
    it "parses and formats consistently" do
      inputs = [
        "b20240515",
        "b20240515.2",
        "b20240515beta",
        "b20240515.3cuttingedge",
        "Re;fx b20240515",
        "Re;fx b20240515.4",
        "Re;fx b20240515tourney",
      ]

      inputs.each do |input|
        parsed = OsuVersion.parse(input)
        parsed.should_not be_nil
        parsed.not_nil!.to_s.should eq input
      end
    end
  end
end
