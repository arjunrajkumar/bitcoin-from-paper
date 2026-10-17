require "test_helper"
require "sqlite3"
require "tmpdir"
require "open3"
require "timeout"

class ConcurrentSpendingTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test "two independent connections cannot both save a spend of one output" do
    Dir.mktmpdir("spending-test-") do |directory|
      path = File.join(directory, "competing.sqlite3")
      database = SQLite3::Database.new(path)
      database.execute("PRAGMA foreign_keys = ON")
      database.execute("PRAGMA journal_mode = WAL")
      database.execute_batch(File.read(Rails.root.join("db/structure.sql")))
      database.execute("INSERT INTO transactions (id, inputs, outputs, created_at, updated_at) VALUES (?, ?, ?, ?, ?)", [
        "a" * 64,
        JSON.generate([{ previous_transaction_id: "f" * 64, output_index: 0, script_sig: "prepared-state" }]),
        JSON.generate([{ value: "2.0", script_pub_key: { operation: "OP_CHECKSIG", public_key: "prepared-owner" } }]),
        "2026-10-17", "2026-10-17"
      ])
      database.execute("INSERT INTO unspent_outputs VALUES (?, ?)", ["a" * 64, 0])
      database.close

      script = <<~RUBY
        require #{Rails.root.join("config/environment").to_s.inspect}
        STDOUT.sync = true
        transaction = Transaction.new(
          inputs: [{ previous_transaction_id: "a" * 64, output_index: 0, script_sig: "proof" }],
          outputs: [{ value: "2", script_pub_key: { operation: "OP_CHECKSIG", public_key: ARGV.fetch(0) } }]
        )
        puts JSON.generate(ready: transaction.valid?, errors: transaction.errors.full_messages)
        raise "Missing start signal" unless STDIN.gets == "start\n"
        saved = transaction.save
        puts JSON.generate(saved: saved, id: transaction.id, errors: transaction.errors.full_messages)
      RUBY
      workers = ["alice", "bob"].map do |receiver|
        Open3.popen3({ "RAILS_ENV" => "test", "DATABASE_URL" => "sqlite3:#{path}" }, RbConfig.ruby, "-e", script, receiver)
      end
      results = Timeout.timeout(30) do
        workers.each do |_input, output, error, _thread|
          line = output.gets
          assert_not_nil line, error.read unless line
          assert_equal({ "ready" => true, "errors" => [] }, JSON.parse(line))
        end
        workers.each { |input, _output, _error, _thread| input.puts("start"); input.flush }
        workers.map do |_input, output, error, thread|
          result = JSON.parse(output.readline)
          assert thread.value.success?, error.read
          result
        end
      end
      assert_equal [false, true], results.map { |result| result.fetch("saved") }.sort_by(&:to_s)
      winner = results.find { |result| result.fetch("saved") }
      loser = results.find { |result| !result.fetch("saved") }
      assert_equal [], winner.fetch("errors")
      assert_equal ["Inputs item 0 references a missing or spent output"], loser.fetch("errors")
      database = SQLite3::Database.new(path)
      assert_equal 2, database.get_first_value("SELECT count(*) FROM transactions")
      assert_equal [[winner.fetch("id"), 0]], database.execute("SELECT transaction_id, output_index FROM unspent_outputs")
    ensure
      workers&.each do |input, output, error, thread|
        Process.kill("KILL", thread.pid) if thread.alive?
        thread.join
        [input, output, error].each(&:close)
      end
      database&.close unless database&.closed?
    end
  end
end
