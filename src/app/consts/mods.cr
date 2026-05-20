@[Flags]
enum Mods : UInt32
  NOMOD       = 0
  NOFAIL      = 1 << 0
  EASY        = 1 << 1
  TOUCHSCREEN = 1 << 2
  HIDDEN      = 1 << 3
  HARDROCK    = 1 << 4
  SUDDENDEATH = 1 << 5
  DOUBLETIME  = 1 << 6
  RELAX       = 1 << 7
  HALFTIME    = 1 << 8
  NIGHTCORE   = 1 << 9
  FLASHLIGHT  = 1 << 10
  AUTOPLAY    = 1 << 11
  SPUNOUT     = 1 << 12
  AUTOPILOT   = 1 << 13
  PERFECT     = 1 << 14
  KEY4        = 1 << 15
  KEY5        = 1 << 16
  KEY6        = 1 << 17
  KEY7        = 1 << 18
  KEY8        = 1 << 19
  FADEIN      = 1 << 20
  RANDOM      = 1 << 21
  CINEMA      = 1 << 22
  TARGET      = 1 << 23
  KEY9        = 1 << 24
  KEYCOOP     = 1 << 25
  KEY1        = 1 << 26
  KEY3        = 1 << 27
  KEY2        = 1 << 28
  SCOREV2     = 1 << 29
  MIRROR      = 1 << 30

  SPEED_CHANGING = DOUBLETIME | NIGHTCORE | HALFTIME
  GAME_CHANGING  = RELAX | AUTOPILOT
  UNRANKED       = SCOREV2 | AUTOPLAY | TARGET
end

STR_MODS = {
  Mods::NOFAIL      => "NF",
  Mods::EASY        => "EZ",
  Mods::TOUCHSCREEN => "TD",
  Mods::HIDDEN      => "HD",
  Mods::HARDROCK    => "HR",
  Mods::SUDDENDEATH => "SD",
  Mods::DOUBLETIME  => "DT",
  Mods::RELAX       => "RX",
  Mods::HALFTIME    => "HT",
  Mods::NIGHTCORE   => "NC",
  Mods::FLASHLIGHT  => "FL",
  Mods::AUTOPLAY    => "AU",
  Mods::SPUNOUT     => "SO",
  Mods::AUTOPILOT   => "AP",
  Mods::PERFECT     => "PF",
  Mods::FADEIN      => "FI",
  Mods::RANDOM      => "RN",
  Mods::CINEMA      => "CN",
  Mods::TARGET      => "TP",
  Mods::SCOREV2     => "V2",
  Mods::MIRROR      => "MR",
  Mods::KEY1        => "1K",
  Mods::KEY2        => "2K",
  Mods::KEY3        => "3K",
  Mods::KEY4        => "4K",
  Mods::KEY5        => "5K",
  Mods::KEY6        => "6K",
  Mods::KEY7        => "7K",
  Mods::KEY8        => "8K",
  Mods::KEY9        => "9K",
  Mods::KEYCOOP     => "CO",
}

MODS_STR = STR_MODS.invert

def conv_mods(mods : Mods) : String
  return "NM" if mods.value == 0

  o = String.build do |str|
    Mods.each do |mod|
      str << STR_MODS[mod] if mods.includes?(mod) && STR_MODS.has_key?(mod)
    end
  end

  o = o.gsub("DT", "") if mods.includes?(Mods::NIGHTCORE)
  o = o.gsub("SD", "") if mods.includes?(Mods::PERFECT)

  o
end

def conv_str(mods : String) : Mods
  return Mods::NOMOD if mods.empty? || mods == "NM"

  res = Mods::NOMOD

  mods.each_char.each_slice(2) do |p|
    if mod = MODS_STR[p.join.upcase]?
      res |= mod
    end
  end

  res
end
