struct OsuVersion
  getter date : String
  getter revision : Int32?
  getter stream : String
  getter is_refx : Bool

  VERSION_REGEX = /^(?<ver>b|Re;fx b)(?<date>\d{8})(?:\.(?<revision>\d+))?(?<stream>stable|beta|cuttingedge|tourney|dev)?$/

  def initialize(@date : String, @revision : Int32?, @stream : String, @is_refx : Bool = false)
  end

  def self.parse(raw : String) : self?
    m = VERSION_REGEX.match(raw)
    return nil unless m

    revision = m["revision"]?.try(&.to_i)
    stream   = m["stream"]? || "stable"
    is_refx  = m["ver"] == "Re;fx b"

    new(m["date"], revision, stream, is_refx)
  end

  def year : Int32
    @date[0..3].to_i
  end

  def to_s : String
    prefix = @is_refx ? "Re;fx b" : "b"
    base = "#{prefix}#{@date}"
    base += ".#{@revision}" if @revision
    base += @stream unless @stream == "stable"
    base
  end
end
