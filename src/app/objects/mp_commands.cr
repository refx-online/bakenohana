require "./match"
require "../state/match_session"
require "../state/sessions"
require "../packets/packets"
require "../log"

module MpCommandHandler
  def self.handle(p : Player, m : Match, text : String) : Nil
    parts = text.split(' ', remove_empty: true)
    return if parts.size < 2

    cmd  = parts[1].downcase
    args = parts[2..]? || [] of String

    is_host = p.same?(m.host)

    case cmd
    when "help"
      lines = [
        "!mp start [seconds] — start the match",
        "!mp abort           — abort in-progress match",
        "!mp kick <name>     — kick a player",
        "!mp host <name>     — transfer host",
        "!mp map <id>        — change map by beatmap id",
        "!mp mods <mods>     — set match mods (e.g. HDDT, NM)",
        "!mp set <teamtype> [wincondition] — set match settings",
        "!mp size <n>        — lock slots beyond n",
        "!mp password [pw]   — change or clear password",
        "!mp invite <name>   — invite a player",
        "!mp close           — close the match",
      ]
      lines.each { |l| m.chat.send_msg(l, PlayerSession.bot, to_self: true) }

    when "start"
      unless is_host
        m.chat.send_msg("only the host can start the match.", PlayerSession.bot, to_self: true)
        return
      end

      if m.in_progress
        m.chat.send_msg("match is already in progress.", PlayerSession.bot, to_self: true)
        return
      end

      player_count = m.slots.count { |s| s.player }
      if player_count == 0
        m.chat.send_msg("no players in match.", PlayerSession.bot, to_self: true)
        return
      end

      force = args[0]?.try(&.downcase) == "force"
      sec_arg = force ? args[1]? : args[0]?
      seconds = sec_arg.try(&.to_i?) || 0

      unless force
        ready_count = m.slots.count { |s| s.status == SlotStatus::Ready }
        if ready_count == 0
          m.chat.send_msg("no players are ready. use !mp start force to force start.", PlayerSession.bot, to_self: true)
          return
        end
      end

      if seconds > 0
        m.chat.send_msg("match starts in #{seconds} seconds.", PlayerSession.bot, to_self: true)
        spawn do
          sleep seconds.seconds
          next unless m.in_progress == false
          m.start
          m.enqueue_state
        end
      else
        m.start
        m.enqueue_state
      end

    when "abort"
      unless is_host
        m.chat.send_msg("only the host can abort the match.", PlayerSession.bot, to_self: true)
        return
      end

      unless m.in_progress
        m.chat.send_msg("match is not in progress.", PlayerSession.bot, to_self: true)
        return
      end

      m.slots.each do |s|
        if s.status == SlotStatus::Playing || s.status == SlotStatus::Complete
          s.status = SlotStatus::NotReady
        end
      end
      m.reset_players_loaded_status
      m.in_progress = false

      m.enqueue(Packets.match_abort, lobby: false)
      m.enqueue_state
      m.chat.send_msg("match aborted.", PlayerSession.bot, to_self: true)

    when "kick"
      unless is_host
        m.chat.send_msg("only the host can kick players.", PlayerSession.bot, to_self: true)
        return
      end

      name = args.join(' ')
      if name.empty?
        m.chat.send_msg("usage: !mp kick <name>", PlayerSession.bot, to_self: true)
        return
      end

      target = PlayerSession.get(username: name)
      unless target && m.get_slot(target)
        m.chat.send_msg("#{name} is not in this match.", PlayerSession.bot, to_self: true)
        return
      end

      if target.same?(p)
        m.chat.send_msg("you can't kick yourself.", PlayerSession.bot, to_self: true)
        return
      end

      target.leave_match
      m.chat.send_msg("#{name} was kicked from the match.", PlayerSession.bot, to_self: true)

    when "host"
      unless is_host
        m.chat.send_msg("only the host can transfer host.", PlayerSession.bot, to_self: true)
        return
      end

      name = args.join(' ')
      if name.empty?
        m.chat.send_msg("usage: !mp host <name>", PlayerSession.bot, to_self: true)
        return
      end

      target = PlayerSession.get(username: name)
      unless target && m.get_slot(target)
        m.chat.send_msg("#{name} is not in this match.", PlayerSession.bot, to_self: true)
        return
      end

      m.host_id = target.id
      m.host.try(&.enqueue(Packets.match_transfer_host))
      m.enqueue_state
      m.chat.send_msg("#{name} is now the host.", PlayerSession.bot, to_self: true)

    when "map"
      unless is_host
        m.chat.send_msg("only the host can change the map.", PlayerSession.bot, to_self: true)
        return
      end

      map_id = args[0]?.try(&.to_i?)
      unless map_id
        m.chat.send_msg("usage: !mp map <beatmap_id>", PlayerSession.bot, to_self: true)
        return
      end

      m.map_id   = map_id
      m.map_md5  = ""
      m.map_name = "unknown (id: #{map_id})"
      m.unready_players(expected: SlotStatus::Ready)
      m.enqueue_state
      m.chat.send_msg("map changed to beatmap id #{map_id}.", PlayerSession.bot, to_self: true)

    when "mods"
      unless is_host
        m.chat.send_msg("only the host can change mods.", PlayerSession.bot, to_self: true)
        return
      end

      mods_str = args[0]? || "NM"
      mods = conv_str(mods_str)

      m.mods = mods
      m.unready_players(expected: SlotStatus::Ready)
      m.enqueue_state
      m.chat.send_msg("mods set to #{conv_mods(mods)}.", PlayerSession.bot, to_self: true)

    when "set"
      unless is_host
        m.chat.send_msg("only the host can change match settings.", PlayerSession.bot, to_self: true)
        return
      end

      team_type_map = {
        "headtohead" => MatchTeamTypes::HeadToHead,
        "h2h"        => MatchTeamTypes::HeadToHead,
        "tagcoop"    => MatchTeamTypes::TagCoop,
        "teamvs"     => MatchTeamTypes::TeamVs,
        "tagteamvs"  => MatchTeamTypes::TagTeamVs,
      }

      win_cond_map = {
        "score"    => MatchWinConditions::Score,
        "accuracy" => MatchWinConditions::Accuracy,
        "acc"      => MatchWinConditions::Accuracy,
        "combo"    => MatchWinConditions::Combo,
        "scorev2"  => MatchWinConditions::ScoreV2,
        "sv2"      => MatchWinConditions::ScoreV2,
      }

      tt_str = args[0]?.try(&.downcase)
      unless tt_str && team_type_map.has_key?(tt_str)
        m.chat.send_msg("usage: !mp set <headtohead|tagcoop|teamvs|tagteamvs> [score|accuracy|combo|scorev2]", PlayerSession.bot, to_self: true)
        return
      end

      m.team_type = team_type_map[tt_str]

      if wc_str = args[1]?.try(&.downcase)
        if wc = win_cond_map[wc_str]?
          m.win_condition = wc
        end
      end

      m.enqueue_state
      m.chat.send_msg("match settings updated.", PlayerSession.bot, to_self: true)

    when "size"
      unless is_host
        m.chat.send_msg("only the host can change match size.", PlayerSession.bot, to_self: true)
        return
      end

      n = args[0]?.try(&.to_i?)
      unless n && 1 <= n <= 16
        m.chat.send_msg("usage: !mp size <1-16>", PlayerSession.bot, to_self: true)
        return
      end

      m.slots.each_with_index do |s, i|
        if i >= n
          if s.player
            s.player.not_nil!.leave_match
          else
            s.status = s.status == SlotStatus::Locked ? SlotStatus::Locked : SlotStatus::Locked
          end
        end
      end

      m.enqueue_state
      m.chat.send_msg("match size set to #{n}.", PlayerSession.bot, to_self: true)

    when "password"
      unless is_host
        m.chat.send_msg("only the host can change the password.", PlayerSession.bot, to_self: true)
        return
      end

      new_pw = args.join(' ')
      m.passwd = new_pw
      m.enqueue_state

      if new_pw.empty?
        m.chat.send_msg("password removed.", PlayerSession.bot, to_self: true)
      else
        m.chat.send_msg("password changed.", PlayerSession.bot, to_self: true)
      end

    when "invite"
      name = args.join(' ')
      if name.empty?
        m.chat.send_msg("usage: !mp invite <name>", PlayerSession.bot, to_self: true)
        return
      end

      target = PlayerSession.get(username: name)
      unless target
        m.chat.send_msg("#{name} is not online.", PlayerSession.bot, to_self: true)
        return
      end

      target.enqueue(Packets.match_invite(p.username, p.id, target.username, m.embed))
      m.chat.send_msg("#{name} has been invited.", PlayerSession.bot, to_self: true)

    when "close"
      unless is_host
        m.chat.send_msg("only the host can close the match.", PlayerSession.bot, to_self: true)
        return
      end

      m.slots.each do |s|
        s.player.try(&.leave_match)
      end

    else
      m.chat.send_msg("unknown command: !mp #{cmd}. type !mp help for a list.", PlayerSession.bot, to_self: true)
    end
  end
end
