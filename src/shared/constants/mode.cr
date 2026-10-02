enum Gamemode : UInt8
  VN_OSU   = 0
  VN_TAIKO = 1
  VN_CATCH = 2
  VN_MANIA = 3

  RX_OSU   = 4
  RX_TAIKO = 5
  RX_CATCH = 6

  AP_OSU = 7

  CHEAT_OSU   = 8
  CHEAT_TAIKO = 9
  CHEAT_CATCH = 10
  CHEAT_MANIA = 11

  CHEAT_RX_OSU   = 12
  CHEAT_RX_TAIKO = 13
  CHEAT_RX_CATCH = 14

  CHEAT_AP_OSU = 15

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

  # Per-mode rank status packed into one 64-bit mask: 3 bits per mode id
  # (0-15). Statuses aren't contiguous (-2 unused): -3->0, -1->1, 0->2,
  # 1->3, 2->4, 3->5, 4->6, 5->7. Mirrors forlorn.
  private def self.status_code(status : Int) : UInt64
    case status
    when -3 then 0_u64
    when -1 then 1_u64
    when 0  then 2_u64
    when 1  then 3_u64
    when 2  then 4_u64
    when 3  then 5_u64
    when 4  then 6_u64
    when 5  then 7_u64
    else          2_u64
    end
  end

  private def self.code_status(code : UInt64) : Int32
    case code & 0b111_u64
    when 0 then -3
    when 1 then -1
    when 2 then 0
    when 3 then 1
    when 4 then 2
    when 5 then 3
    when 6 then 4
    when 7 then 5
    else         0
    end
  end

  def self.status_at(mask : Int, mode : Int) : Int32
    return 0 unless 0 <= mode <= 15
    code_status(mask.to_u64 >> (mode * 3))
  end

  def self.with_status(mask : Int, mode : Int, status : Int) : UInt64
    m = mask.to_u64
    return m unless 0 <= mode <= 15
    code = status_code(status)
    shift = (mode * 3).to_u64
    (m & ~(0b111_u64 << shift)) | (code << shift)
  end

  def self.all_modes_status(status : Int) : UInt64
    code = status_code(status)
    (0...16).reduce(0_u64) { |mask, mode| mask | (code << (mode * 3)) }
  end

  def cheat? : Bool
    {Gamemode::CHEAT_OSU, Gamemode::CHEAT_TAIKO, Gamemode::CHEAT_CATCH, Gamemode::CHEAT_MANIA,
     Gamemode::CHEAT_RX_OSU, Gamemode::CHEAT_RX_TAIKO, Gamemode::CHEAT_RX_CATCH,
     Gamemode::CHEAT_AP_OSU}.includes?(self)
  end

  def as_vn : UInt8    # NOTE: explicit match, never derive it —
    # ap ids would land on the wrong game (7 % 4 == 3 == mania).
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
