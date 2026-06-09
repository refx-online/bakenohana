require "../../../infrastructure/performance/performance_calculator"
require "../../../shared/constants/mods"
require "../../../persistence/repositories/beatmap"
require "../../../infrastructure/redis/redis_client"
require "http/client"
require "json"

macro arg(name, type, required = true, default = nil)
end

macro command(name, description, *args, aliases = [] of String, priv = nil, &block)
  arg_names = [] of String
  arg_types = [] of String
  arg_required = [] of Bool
  arg_defaults = [] of String

  # NOTE: kinda cursed lelw
  # https://crystal-lang.org/reference/1.16/syntax_and_semantics/macros/index.html
  {% for arg in args %}
    {% if arg.is_a?(Call) && arg.name == "arg" %}
      arg_names << {{arg.args[0]}}
      arg_types << {{arg.args[1].stringify}}
      arg_required << {{arg.args[2] || true}}
      arg_defaults << {{arg.args[3] ? arg.args[3].stringify : "nil"}}
    {% end %}
  {% end %}

  _proc = ->(player : Player, parsed_args : Hash(String, String)) { {{block.body}} }
  {% if priv == nil %}
    _priv = nil.as(Privileges?)
  {% else %}
    _priv = {{priv}}.as(Privileges?)
  {% end %}
  @@commands[{{name}}] = { {{description}}, arg_names, _proc, _priv }
  {% if !aliases.empty? %}
    @@command_aliases[{{name}}] = [{% for a in aliases %}{{a}}, {% end %}] of String
    {% for a in aliases %}
      @@commands[{{a}}] = { {{description}}, arg_names, _proc, _priv }
      @@alias_set.add({{a}})
    {% end %}
  {% end %}
end

class CommandHandler
  @@commands = {} of String => {String, Array(String), Proc(Player, Hash(String, String), Nil), Privileges?}
  @@alias_set = Set(String).new
  @@command_aliases = {} of String => Array(String)

  command "help", "show available commands" do
    help_text = ["available bot commands:"]
    @@commands.each do |cmd, (desc, args, _, req_priv)|
      next if @@alias_set.includes?(cmd)
      next if req_priv && !player.priv.includes?(req_priv)
      aliases = @@command_aliases[cmd]?
      alias_str = aliases && !aliases.empty? ? " (alias: #{aliases.join(", ")})" : ""
      usage = args.empty? ? "#{cmd}#{alias_str}" : "#{cmd}#{alias_str} #{args.map { |a| "<#{a}>" }.join(" ")}"
      help_text << "#{Config.boat_prefix}#{usage} - #{desc}"
    end
    player.send_msg(help_text.join('\n'), PlayerSession.bot)
  end

  command "ping", "pong" do
    player.send_msg("pong!", PlayerSession.bot)
  end

  command "time", "show current server time" do
    current_time = Time.local.to_s("%Y-%m-%d %H:%M:%S")
    player.send_msg("current server time: #{current_time}", PlayerSession.bot)
  end

  command "roll", "roll a dice",
    arg("min", "int", false, "0"),
    arg("max", "int", false, "100") do

    if parsed_args.size == 1 && parsed_args["min"]? && !parsed_args["max"]?
      max = parsed_args["min"]?.try(&.to_i) || 100
      min = 0
    else
      min = parsed_args["min"]?.try(&.to_i) || 0
      max = parsed_args["max"]?.try(&.to_i) || 100
    end

    if min >= max
      return player.send_msg("min must be less than max!", PlayerSession.bot)
    end

    num = Random.rand(min..max)
    range_text = (min == 0 && max == 100) ? "" : " (#{min}-#{max})"
    player.send_msg("#{player.username} rolled #{num}!#{range_text}", PlayerSession.bot)
  end

  command "sex", "sex." do
    player.send_msg(
      "When bro starts whining and begging me to go faster " \
      "so I have to slowly grind against his special spot with " \
      "my tip and that causes bro " \
      "to start sniffing with pleading tears in his pretty eyes, " \
      "I wrap my arms around bro's waist and hush him softly as I whisper in his ear, " \
      "“shh.. it’s okay, bro…” To make sure he’s comfortable, I asked what his color is and he reply’s " \
      "with a trembling, “y-yellow..” So I make sure to cover bro in kisses then once he stops crying he asks, " \
      "“I’m okay now… Can you start moving?” I smile then press another kiss to his lips, " \
      "I begin to pick up the pace again. All while bro is thanking me and after we’re done I " \
      "clean the mess with a wipe and carry him to a warm bath and take care of him. Then when we’re in bed, " \
      "while we’re cuddling he tickles me and I giggle and " \
      "then we fall asleep in each other’s arms, lovesick and kind.",
      PlayerSession.bot
    )
  end

  command "with", "recalculate last /np with given mods",
    arg("mods", "string"), aliases: ["w"] do

    np = player.last_np
    unless np
      return player.send_msg("no map selected — use /np first.", PlayerSession.bot)
    end

    map_id, mode = np
    CommandHandler.calc_with(player, map_id, mode, parsed_args["mods"]? || "NM")
  end

  command "map", "change ranked status of last /np'd map",
    arg("status", "string"), arg("scope", "string"), priv: Privileges::NOMINATOR do

    status_str = parsed_args["status"]?
    scope_str  = parsed_args["scope"]?

    status_map = {"rank" => RankedStatus::Ranked, "unrank" => RankedStatus::Pending,
                  "love" => RankedStatus::Loved,  "qual"   => RankedStatus::Qualified}

    unless status_str && scope_str && status_map.has_key?(status_str) && ["map", "set"].includes?(scope_str)
      return player.send_msg("invalid syntax: #{Config.boat_prefix}map <rank/unrank/love/qual> <map/set>", PlayerSession.bot)
    end

    np = player.last_np
    unless np
      return player.send_msg("please /np a map first!", PlayerSession.bot)
    end

    map_id, _ = np
    bmap = BeatmapRepo.fetch_one(map_id)
    unless bmap
      return player.send_msg("couldn't find that map in the database.", PlayerSession.bot)
    end

    new_status = status_map[status_str]

    if scope_str == "map"
      if bmap.ranked_status == new_status
        return player.send_msg("#{bmap.embed} is already #{new_status}!", PlayerSession.bot)
      end
      BeatmapRepo.update_status(bmap.id, new_status)
    else
      BeatmapRepo.update_set_status(bmap.set_id, new_status)
    end

    RedisService.publish("forlorn:refresh_map", bmap.md5)

    spawn CommandHandler.post_rank_webhook(player, bmap, new_status, scope_str == "set")

    msg = scope_str == "map" ? "#{bmap.embed} has been #{new_status}." : "all maps in the set have been #{new_status}."
    player.send_msg(msg, PlayerSession.bot)
  end

  def self.post_rank_webhook(player : Player, bmap : BeatmapRepo, status : RankedStatus, is_set : Bool)
    webhook_url = Config.discord_rank_webhook
    return unless webhook_url

    color = case status
    when RankedStatus::Ranked, RankedStatus::Approved, RankedStatus::Qualified then 0x6bceff
    when RankedStatus::Loved                                                    then 0xff66aa
    else                                                                             0x808080
    end

    length = bmap.total_length
    fmt_length = if length >= 3600
      "%02d:%02d:%02d" % {length // 3600, (length // 60) % 60, length % 60}
    else
      "%02d:%02d" % {length // 60, length % 60}
    end

    domain = Config.domain
    scope_label = is_set ? "set" : "map"
    title = "#{bmap.artist} - #{bmap.title} [#{bmap.version}] #{bmap.diff.round(2)}★"
    description = "cs: #{bmap.cs} od: #{bmap.od} ar: #{bmap.ar} hp: #{bmap.hp} length: #{fmt_length}"

    payload = {
      "embeds" => [
        {
          "title"       => title,
          "description" => description,
          "url"         => "https://#{domain}/beatmaps/#{bmap.id}",
          "color"       => color,
          "author"      => {
            "name"     => "#{player.username} changed #{scope_label} status to #{status}!",
            "url"      => "https://#{domain}/u/#{player.id}",
            "icon_url" => "https://a.#{domain}/#{player.id}",
          },
          "footer" => {"text" => "mapped by #{bmap.creator}"},
          "image"  => {"url" => "https://b.#{domain}/cover/#{bmap.set_id}"},
        },
      ],
    }

    HTTP::Client.post(
      webhook_url,
      headers: HTTP::Headers{"Content-Type" => "application/json"},
      body: payload.to_json
    )
  rescue ex
    rlog "[webhook] #{ex.message}", Ansi::LRED
  end

  def self.calc_with(player : Player, map_id : Int32, mode : Gamemode, mods_str : String)
    mods = conv_str(mods_str)
    spawn do
      begin
        result = OsuPerformanceCalculator.calculate_score(map_id, mode, mods)
        reply = "+#{conv_mods(mods)} | ★ #{result.stars.round(2)} | FC: #{result.pp.round(2)}pp"
        player.enqueue(Packets.send_message(PlayerSession.bot.username, reply, player.username, 1))
      rescue ex
        player.enqueue(Packets.send_message(PlayerSession.bot.username, "couldn't calculate: #{ex.message}", player.username, 1))
      end
    end
  end

  def self.handle_command(player : Player, command_text : String)
    parts = command_text[Config.boat_prefix.size..-1].strip.split(' ')

    cmd_name = parts[0].downcase
    raw_args = parts[1..-1]? || [] of String

    if cmd_info = @@commands[cmd_name]?
      description, arg_names, handler, req_priv = cmd_info

      if req_priv && !player.priv.includes?(req_priv)
        return player.send_msg(
          "unknown command: #{cmd_name}\n" +
          "type '#{Config.boat_prefix}help' for available commands.",
          PlayerSession.bot
        )
      end

      parsed_args = {} of String => String

      arg_names.each_with_index do |arg_name, i|
        if i < raw_args.size
          parsed_args[arg_name] = raw_args[i]
        end
      end

      handler.call(player, parsed_args)
    else
      player.send_msg(
        "unknown command: #{cmd_name}\n" +
        "type '#{Config.boat_prefix}help' for available commands.",
        PlayerSession.bot
      )
    end
  end
end
