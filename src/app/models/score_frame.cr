struct ScoreFrame
  property time : Int32
  property id : Int32
  property num300 : UInt16
  property num100 : UInt16
  property num50 : UInt16
  property num_geki : UInt16
  property num_katu : UInt16
  property num_miss : UInt16
  property total_score : Int32
  property max_combo : UInt16
  property current_combo : UInt16
  property perfect : Bool
  property current_hp : UInt8
  property tag_byte : UInt8
  property score_v2 : Bool
  property combo_portion : Float64?
  property bonus_portion : Float64?

  def initialize(
    @time = 0,
    @id = 0,
    @num300 = 0_u16,
    @num100 = 0_u16,
    @num50 = 0_u16,
    @num_geki = 0_u16,
    @num_katu = 0_u16,
    @num_miss = 0_u16,
    @total_score = 0,
    @max_combo = 0_u16,
    @current_combo = 0_u16,
    @perfect = false,
    @current_hp = 0_u8,
    @tag_byte = 0_u8,
    @score_v2 = false,
    @combo_portion = nil,
    @bonus_portion = nil
  )
  end
end
