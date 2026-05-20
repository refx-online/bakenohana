struct OsuVersion
  getter date : String
  getter revision : Int32?
  getter stream : String

  VERSION_REGEX = /^b(?<date>\d{8})(?:\.(?<revision>\d+))?(?<stream>stable|beta|cuttingedge|tourney|dev)?$/

  def initialize(@date : String, @revision : Int32?, @stream : String)
  end

  def self.parse(raw : String) : self?
    m = VERSION_REGEX.match(raw)
    return nil unless m

    revision = m["revision"]?.try(&.to_i)
    stream   = m["stream"]? || "stable"

    new(m["date"], revision, stream)
  end

  def to_s : String
    base = "b#{@date}"
    base += ".#{@revision}" if @revision
    base += @stream unless @stream == "stable"
    base
  end
end
