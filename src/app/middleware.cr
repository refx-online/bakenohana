require "./utils"

class Metrics < Kemal::Handler
  def call(env : HTTP::Server::Context)
    s_ = Time.monotonic
    call_next env
    n_ = Time.monotonic
    elap = (n_ - s_).total_nanoseconds

    status = env.response.status_code
    color  = status < 400 ? Ansi::LGREEN : Ansi::LRED

    begin
      host   = env.request.headers["Host"]?
      path   = env.request.path
      method = env.request.method
      rlog "[#{method}] #{status} #{host}#{path}#{Ansi::RESET} | #{Ansi::LBLUE}request took: #{format_time(elap)}", color
    rescue ex
      rlog "[scan?] #{env.request.path} | #{Ansi::LBLUE}request took: #{format_time(elap)}", color
      rlog env.request.to_s
    end

    env.response.headers["process-time"] = (elap / 1_000_000.0).round(2).to_s
  end
end
