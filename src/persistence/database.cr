require "db"
require "mysql"

class Database
  getter db : DB::Database

  # NOTE: mysql kills idle connections (wait_timeout) but crystal-db hands
  # out pooled connections without validating them, so the first query on a
  # reaped connection raises and — worse — the dead conn stays in the pool,
  # turning one hiccup into a permanent outage until restart. every method
  # below retries once on connection-like errors after resetting the pool.
  @reset_mutex = Mutex.new

  def initialize(@url : String)
    @db = DB.open(@url)
  end

  # mysql's various ways of saying "this connection is dead".
  private def connection_error?(ex : Exception) : Bool
    return true if ex.is_a?(IO::Error)
    ex.message.try(&.matches?(/disconnected|gone away|lost connection|broken pipe|connection reset|connection refused|timeout/i)) || false
  end

  private def reset! : Nil
    @reset_mutex.synchronize do
      begin
        @db.close
      rescue
        # already broken — that's why we're here
      end
      @db = DB.open(@url)
    end
  end

  # reads are always safe to retry.
  private def with_retry(&block)
    begin
      yield
    rescue ex
      raise ex unless connection_error?(ex)
      reset!
      yield
    end
  end

  # writes only retry on connection errors — never on real failures, so a
  # rejected write can't double-apply.
  private def with_retry_write(&block)
    begin
      yield
    rescue ex : Exception
      raise ex unless connection_error?(ex)
      reset!
      yield
    end
  end

  def fetch_one(type : T.class, query : String, *params) : T? forall T
    args = params.size > 0 ? params.to_a : [] of DB::Any
    with_retry { @db.query_one?(query, args: args, as: type) }
  end

  def fetch_all(type : T.class, query : String, *params) : Array(T) forall T
    # compiler was ANGGGGRRRRRRRRRRRY
    args = Tuple.new(*params.map(&.as(DB::Any)))
    results = [] of T

    with_retry do
      @db.query(query, *args) do |rs|
        rs.each do
          results << rs.read(type)
        end
      end
    end

    results
  end

  def fetch_val(query : String, *params, column : Int32 = 0) : DB::Any?
    args = params.size > 0 ? params.to_a : [] of DB::Any
    with_retry do
      @db.query_one?(query, args: args) do |rs|
        rs.read(DB::Any)
      end
    end
  end

  def execute(query : String, *params) : DB::ExecResult
    args = params.size > 0 ? params.to_a : [] of DB::Any
    with_retry_write { @db.exec(query, args: args) }
  end

  def execute(query : String, args : Array(DB::Any)) : DB::ExecResult
    with_retry_write { @db.exec(query, args: args) }
  end

  def transaction(&block : DB::Transaction ->)
    with_retry_write do
      @db.transaction do |tx|
        block.call(tx)
      end
    end
  end
end
