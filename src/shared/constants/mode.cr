enum Gamemode : UInt8
  VN_OSU   = 0
  VN_TAIKO = 1
  VN_CATCH = 2
  VN_MANIA = 3

  RX_OSU   = 4
  RX_TAIKO = 5
  RX_CATCH = 6

  AP_OSU = 8

  CHEAT_OSU   = 12
  CHEAT_TAIKO = 13
  CHEAT_CATCH = 14
  CHEAT_MANIA = 15

  CHEAT_RX_OSU   = 21
  CHEAT_RX_TAIKO = 22
  CHEAT_RX_CATCH = 23

  CHEAT_AP_OSU = 24

  def self.from_params(vn : UInt8, mods : Mods) : Gamemode
    if mods.includes?(Mods::AUTOPILOT) && vn == 0
      Gamemode::AP_OSU
    elsif mods.includes?(Mods::RELAX) && vn != 3
      Gamemode.new((vn + 4).to_u8)
    else
      Gamemode.new(vn)
    end
  end

  def self.valid_gamemodes : Array(Gamemode)
    VALID_GAMEMODES
  end

  def cheat? : Bool
    {Gamemode::CHEAT_OSU, Gamemode::CHEAT_TAIKO, Gamemode::CHEAT_CATCH, Gamemode::CHEAT_MANIA,
     Gamemode::CHEAT_RX_OSU, Gamemode::CHEAT_RX_TAIKO, Gamemode::CHEAT_RX_CATCH,
     Gamemode::CHEAT_AP_OSU}.includes?(self)
  end

  def as_vn : UInt8    # NOTE: explicit match, never value % 4 — cheat-rx ids (21+) would
    # land on the wrong game (21 % 4 == 1 == taiko).
    case self
    when VN_OSU, RX_OSU, AP_OSU, CHEAT_OSU, CHEAT_RX_OSU, CHEAT_AP_OSU then 0_u8
    when VN_TAIKO, RX_TAIKO, CHEAT_TAIKO, CHEAT_RX_TAIKO               then 1_u8
    when VN_CATCH, RX_CATCH, CHEAT_CATCH, CHEAT_RX_CATCH               then 2_u8
    else                                                                    3_u8
    end
  end

  def to_s : String
    case self
    when VN_OSU       then "vn!std"
    when VN_TAIKO     then "vn!taiko"
    when VN_CATCH     then "vn!catch"
    when VN_MANIA     then "vn!mania"
    when RX_OSU       then "rx!std"
    when RX_TAIKO     then "rx!taiko"
    when RX_CATCH     then "rx!catch"
    when AP_OSU       then "ap!std"
    when CHEAT_OSU    then "cheat!std"
    when CHEAT_TAIKO  then "cheat!taiko"
    when CHEAT_CATCH  then "cheat!catch"
    when CHEAT_MANIA  then "cheat!mania"
    when CHEAT_RX_OSU   then "cheat-rx!std"
    when CHEAT_RX_TAIKO then "cheat-rx!taiko"
    when CHEAT_RX_CATCH then "cheat-rx!catch"
    when CHEAT_AP_OSU then "cheat-ap!std"
    else                   "vn!std"
    end
  end
end

VALID_GAMEMODES = [
  Gamemode::VN_OSU, Gamemode::VN_TAIKO, Gamemode::VN_CATCH, Gamemode::VN_MANIA,
  Gamemode::RX_OSU, Gamemode::RX_TAIKO, Gamemode::RX_CATCH,
  Gamemode::AP_OSU,
  Gamemode::CHEAT_OSU, Gamemode::CHEAT_TAIKO, Gamemode::CHEAT_CATCH, Gamemode::CHEAT_MANIA,
  Gamemode::CHEAT_RX_OSU, Gamemode::CHEAT_RX_TAIKO, Gamemode::CHEAT_RX_CATCH,
  Gamemode::CHEAT_AP_OSU,
]
