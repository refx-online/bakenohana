MODE_STR_LIST = {
  "vn!std",
  "vn!taiko",
  "vn!catch",
  "vn!mania",
  "rx!std",
  "rx!taiko",
  "rx!catch",
  "rx!mania",
  "ap!std",
  "ap!taiko",
  "ap!catch",
  "ap!mania",
  "cheat!std",
  "cheat!taiko",
  "cheat!catch",
  "cheat!mania",
  "cheatcheat!std",
  "cheatcheat!taiko",
  "cheatcheat!catch",
  "cheatcheat!mania",
  "td!std",
}

enum Gamemode : UInt8
  VN_OSU
  VN_TAIKO
  VN_CATCH
  VN_MANIA
  RX_OSU
  RX_TAIKO
  RX_CATCH
  RX_MANIA
  AP_OSU
  AP_TAIKO
  AP_CATCH
  AP_MANIA
  CHEAT_OSU
  CHEAT_TAIKO
  CHEAT_CATCH
  CHEAT_MANIA
  CHEAT_CHEAT_OSU
  CHEAT_CHEAT_TAIKO
  CHEAT_CHEAT_CATCH
  CHEAT_CHEAT_MANIA
  TOUCH_DEVICE_OSU

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

  def as_vn : UInt8
    (self.value % 4).to_u8
  end

  def to_s : String
    MODE_STR_LIST[self.value]
  end
end

VALID_GAMEMODES = Gamemode.values.reject { |gm|
  {Gamemode::RX_MANIA, Gamemode::AP_TAIKO, Gamemode::AP_CATCH, Gamemode::AP_MANIA}.includes?(gm)
}
