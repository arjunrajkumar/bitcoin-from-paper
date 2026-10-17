require "test_helper"
require "sqlite3"
require Rails.root.join("db/migrate/20261015000016_use_hash_identities")
require Rails.root.join("db/migrate/20261015000017_replace_transaction_fields_with_inputs_and_outputs")

class UnspentOutputMigrationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class UnspentOutputMigrationTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  self.use_transactional_tests = false

  setup do
    require Rails.root.join("db/migrate/20261017000018_create_unspent_outputs")
  end

  test "existing transactions stop migration before changing history or schema" do
    with_step_two_tables do |connection|
      connection.execute("INSERT INTO transactions (id, created_at, updated_at) VALUES ('#{'a' * 64}', '2026-10-17', '2026-10-17')")
      schema = connection.select_rows("SELECT name, sql FROM sqlite_master ORDER BY name")
      history = connection.select_rows("SELECT * FROM transactions")
      error = assert_raises(ActiveRecord::MigrationError) do
        capture_io { CreateUnspentOutputs.new.exec_migration(connection, :up) }
      end
      assert_equal "Unspent output migration requires an empty transactions table", error.message.strip
      assert_equal schema, connection.select_rows("SELECT name, sql FROM sqlite_master ORDER BY name")
      assert_equal history, connection.select_rows("SELECT * FROM transactions")
    end
  end

  test "migration preserves other records and rollback removes only the output set" do
    with_step_two_tables do |connection|
      connection.execute("INSERT INTO blocks (id, height, created_at, updated_at) VALUES ('#{'a' * 64}', 0, '2026-10-17', '2026-10-17')")
      connection.execute("INSERT INTO candidate_blocks (id, identity_seed, created_at, updated_at) VALUES ('#{'b' * 64}', '#{'c' * 64}', '2026-10-17', '2026-10-17')")
      connection.execute("INSERT INTO nodes (id, identity_seed, candidate_block_id, created_at, updated_at) VALUES ('#{'d' * 64}', '#{'e' * 64}', '#{'b' * 64}', '2026-10-17', '2026-10-17')")
      retained = %w[blocks nodes candidate_blocks].to_h { |table| [table, connection.select_rows("SELECT * FROM #{table}")] }
      capture_io { CreateUnspentOutputs.new.exec_migration(connection, :up) }
      assert_equal %w[output_index transaction_id], connection.columns(:unspent_outputs).map(&:name).sort
      assert_equal %w[transaction_id output_index], connection.primary_keys(:unspent_outputs)
      assert_includes connection.select_value("SELECT sql FROM sqlite_master WHERE name = 'unspent_outputs'"), "WITHOUT ROWID"
      assert_equal [["transactions", :cascade]], connection.foreign_keys(:unspent_outputs).map { |key| [key.to_table, key.on_delete] }
      assert_equal 8, connection.select_value("SELECT count(*) FROM sqlite_master WHERE type = 'trigger'")
      retained.each { |table, rows| assert_equal rows, connection.select_rows("SELECT * FROM #{table}") }
      capture_io { CreateUnspentOutputs.new.exec_migration(connection, :down) }
      assert_not connection.table_exists?(:unspent_outputs)
      retained.each { |table, rows| assert_equal rows, connection.select_rows("SELECT * FROM #{table}") }
    end
  end

  test "SQL structure restores unique references foreign keys and integer position bounds" do
    database = SQLite3::Database.new(":memory:")
    database.execute("PRAGMA foreign_keys = ON")
    database.execute_batch(File.read(Rails.root.join("db/structure.sql")))
    database.execute("INSERT INTO transactions (id, created_at, updated_at) VALUES (?, ?, ?)", ["a" * 64, "2026-10-17", "2026-10-17"])
    [0, 1, 4_294_967_295].each do |index|
      database.execute("INSERT INTO unspent_outputs (transaction_id, output_index) VALUES (?, ?)", ["a" * 64, index])
    end
    error = assert_raises(SQLite3::ConstraintException) do
      database.execute("INSERT INTO unspent_outputs VALUES (?, ?)", ["a" * 64, 0])
    end
    assert_equal "UNIQUE constraint failed: unspent_outputs.transaction_id, unspent_outputs.output_index", error.message
    error = assert_raises(SQLite3::ConstraintException) do
      database.execute("INSERT INTO unspent_outputs VALUES (?, ?)", ["f" * 64, 0])
    end
    assert_equal "FOREIGN KEY constraint failed", error.message
    [-1, 4_294_967_296, 0.5].each do |index|
      error = assert_raises(SQLite3::ConstraintException) do
        database.execute("INSERT INTO unspent_outputs VALUES (?, ?)", ["a" * 64, index])
      end
      assert_equal "CHECK constraint failed: unspent_outputs_position", error.message
    end
    assert_equal [0, 1, 4_294_967_295], database.execute("SELECT output_index FROM unspent_outputs ORDER BY output_index").flatten
    database.execute("DELETE FROM transactions")
    assert_equal 0, database.get_first_value("SELECT count(*) FROM unspent_outputs")
  ensure
    database&.close
  end

  private

  def with_step_two_tables
    UnspentOutputMigrationRecord.establish_connection(adapter: "sqlite3", database: ":memory:")
    UnspentOutputMigrationRecord.connection_pool.with_connection do |connection|
      %w[blocks transactions nodes candidate_blocks].each { |table| connection.create_table(table) }
      capture_io do
        UseHashIdentities.new.exec_migration(connection, :up)
        ReplaceTransactionFieldsWithInputsAndOutputs.new.exec_migration(connection, :up)
      end
      yield connection
    end
  ensure
    UnspentOutputMigrationRecord.connection_pool.disconnect!
  end
end
