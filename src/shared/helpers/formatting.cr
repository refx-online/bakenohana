def format_time(ns : Float64) : String
  suffixes = ["n", "μs", "ms", "s"]
  i = 0
  while ns >= 1000 && i < suffixes.size - 1
    ns /= 1000.0
    i += 1
  end
  "#{ns.round(2)} #{suffixes[i]}"
end
