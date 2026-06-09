require "../infrastructure/redis/redis_client"
require "../state/player_session"
require "../persistence/repositories/stats"
require "../transport/protocol/packets"
require "../infrastructure/logging/logger"

module PubSub
  CHANNELS = [
    "refx:notify",
    "refx:restrict",
    "refx:refresh_stats",
    "refx:recalculate",
  ]

  def self.start
    spawn do
      rlog "pubsub loop started, subscribing to: #{CHANNELS.join(", ")}", Ansi::LCYAN

      begin
        RedisService.sub.subscribe("refx:notify", "refx:restrict", "refx:refresh_stats", "refx:recalculate") do |on|
          on.message do |channel, payload|
            rlog "[pubsub] #{channel}: #{payload}", Ansi::LBLUE
            handle(channel, payload)
          end
        end
      rescue ex
        rlog "[pubsub] loop crashed: #{ex.message}", Ansi::LRED
        rlog ex.backtrace.join("\n"), Ansi::LRED
      end
    end
  end

  private def self.handle(channel : String, payload : String) : Nil
    case channel
    when "refx:notify"
      # payload: "user_id|message"
      parts = payload.split("|", 2)
      return unless parts.size == 2

      user_id = parts[0].to_i?
      message = parts[1]
      return unless user_id

      player = PlayerSession.get(id: user_id)
      return unless player

      player.enqueue(Packets.notification(message))
      rlog "[pubsub] notified #{player.username}: #{message}", Ansi::LGREEN

    when "refx:restrict"
      # payload: "user_id|reason"
      parts = payload.split("|", 2)
      return unless parts.size == 2

      user_id = parts[0].to_i?
      reason  = parts[1]
      return unless user_id

      player = PlayerSession.get(id: user_id)
      return unless player

      player.rem_priv(Privileges::UNRESTRICTED)
      player.enqueue(Packets.account_restricted)
      player.enqueue(Packets.notification("you have been restricted: #{reason}"))

      # remove from leaderboards
      Gamemode.values.each do |mode|
        next unless Gamemode.valid_gamemodes.includes?(mode)
        RedisService.zrem(RedisService.leaderboard_key(mode.value.to_i), player.id)
        RedisService.zrem(RedisService.country_leaderboard_key(mode.value.to_i, player.status.country), player.id)
      end

      rlog "[pubsub] restricted #{player.username}: #{reason}", Ansi::LRED

    when "refx:refresh_stats"
      # payload: "user_id"
      user_id = payload.to_i?
      return unless user_id

      player = PlayerSession.get(id: user_id)
      return unless player

      player.load_stats
      player.update_leaderboards

      unless player.restricted
        stats_packet = Packets.user_stats(player)
        PlayerSession.each do |p, _|
          p.enqueue(stats_packet)
        end
      end

      rlog "[pubsub] refreshed stats for #{player.username}", Ansi::LGREEN

    when "refx:recalculate"
      # payload: "user_id"
      user_id = payload.to_i?
      return unless user_id

      player = PlayerSession.get(id: user_id)
      return unless player

      player.load_stats
      player.update_leaderboards

      unless player.restricted
        stats_packet = Packets.user_stats(player)
        PlayerSession.each do |p, _|
          p.enqueue(stats_packet)
        end
      end

      player.send_msg("recalculation done!", PlayerSession.bot)
      rlog "[pubsub] recalculate done for #{player.username}", Ansi::LGREEN
    end
  rescue ex
    rlog "[pubsub] handler error on #{channel}: #{ex.message}", Ansi::LRED
  end
end
