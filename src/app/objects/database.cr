require "db"
require "mysql"

class Database
  getter db : DB::Database

  def initialize(@url : String)
    @db = DB.open(@url)
  end

  def fetch_one(type : T.class, query : String, *params) : T? forall T
    args = params.size > 0 ? params.to_a : [] of DB::Any
    @db.query_one?(query, args: args, as: type)
  end

  def fetch_all(type : T.class, query : String, *params) : Array(T) forall T
    # compiler was ANGGGGRRRRRRRRRRRY
    args = Tuple.new(*params.map(&.as(DB::Any)))
    results = [] of T

    @db.query(query, *args) do |rs|
      rs.each do
        results << rs.read(type)
      end
    end

    results
  end

  def fetch_val(query : String, *params, column : Int32 = 0) : DB::Any?
    args = params.size > 0 ? params.to_a : [] of DB::Any
    @db.query_one?(query, args: args) do |rs|
      rs.read(DB::Any)
    end
  end

  def execute(query : String, *params) : DB::ExecResult
    args = params.size > 0 ? params.to_a : [] of DB::Any
    @db.exec(query, args: args)
  end

  def execute(query : String, args : Array(DB::Any)) : DB::ExecResult
    @db.exec(query, args: args)
  end

  def transaction(&block : DB::Transaction ->)
    @db.transaction do |tx|
      block.call(tx)
    end
  end
end
