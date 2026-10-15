require "test_helper"
require "sqlite3"
require Rails.root.join("db/migrate/20261015000016_use_hash_identities")
require Rails.root.join("db/migrate/20261015000017_replace_transaction_fields_with_inputs_and_outputs")

class TransactionStructureMigrationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class TransactionStructureMigrationTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  self.use_transactional_tests = false

  test "existing transactions or blocks stop the migration without changing data or schema" do
    [%w[transactions], %w[blocks], %w[transactions blocks]].each do |populated|
      with_step_one_tables do |connection|
        populated.each do |table|
          fields = table == "blocks" ? ", height" : ""
          values = table == "blocks" ? ", 0" : ""
          connection.execute("INSERT INTO #{table} (id, created_at, updated_at#{fields}) VALUES ('#{'a' * 64}', '2026-10-15', '2026-10-15'#{values})")
        end
        schema = connection.select_rows("SELECT name, sql FROM sqlite_master ORDER BY name")
        contents = populated.to_h { |table| [table, connection.select_rows("SELECT * FROM #{table}")] }
        error = assert_raises(ActiveRecord::MigrationError) do
          capture_io { ReplaceTransactionFieldsWithInputsAndOutputs.new.exec_migration(connection, :up) }
        end
        assert_equal "Transaction structure migration requires empty tables: #{populated.join(', ')}", error.message.strip
        assert_equal schema, connection.select_rows("SELECT name, sql FROM sqlite_master ORDER BY name")
        contents.each { |table, rows| assert_equal rows, connection.select_rows("SELECT * FROM #{table}") }
      end
    end
  end

  test "empty replacement keeps nodes candidates hash keys and foreign keys" do
    with_step_one_tables do |connection|
      connection.execute("INSERT INTO candidate_blocks (id, identity_seed, created_at, updated_at) VALUES ('#{'a' * 64}', '#{'b' * 64}', '2026-10-15', '2026-10-15')")
      connection.execute("INSERT INTO nodes (id, identity_seed, candidate_block_id, created_at, updated_at) VALUES ('#{'c' * 64}', '#{'d' * 64}', '#{'a' * 64}', '2026-10-15', '2026-10-15')")
      retained = %w[nodes candidate_blocks].to_h { |table| [table, connection.select_rows("SELECT * FROM #{table}")] }
      capture_io { ReplaceTransactionFieldsWithInputsAndOutputs.new.exec_migration(connection, :up) }
      retained.each { |table, rows| assert_equal rows, connection.select_rows("SELECT * FROM #{table}") }
      assert_equal %w[block_id created_at id inputs outputs updated_at], connection.columns(:transactions).map(&:name).sort
      assert_includes connection.select_value("SELECT sql FROM sqlite_master WHERE name = 'transactions'"), "WITHOUT ROWID"
      assert_equal ["blocks"], connection.foreign_keys(:transactions).map(&:to_table)
      assert_equal 8, connection.select_value("SELECT count(*) FROM sqlite_master WHERE type = 'trigger'")
      error = assert_raises(ActiveRecord::IrreversibleMigration) do
        capture_io { ReplaceTransactionFieldsWithInputsAndOutputs.new.exec_migration(connection, :down) }
      end
      assert_equal "Input and output lists cannot be converted back to the old transaction fields. Restore the pre-migration database backup.", error.message.strip
    end
  end

  test "saved SQL restores protection for both lists and the block reference" do
    database = SQLite3::Database.new(":memory:")
    database.execute("PRAGMA foreign_keys = ON")
    database.execute_batch(File.read(Rails.root.join("db/structure.sql")))
    inputs = [{ previous_transaction_id: "b" * 64, output_index: 0, script_sig: "proof" }].to_json
    outputs = [{ value: "1.0", script_pub_key: { operation: "OP_CHECKSIG", public_key: "key" } }].to_json
    database.execute("INSERT INTO transactions (id, inputs, outputs, created_at, updated_at) VALUES (?, ?, ?, ?, ?)", ["a" * 64, inputs, outputs, "2026-10-15", "2026-10-15"])
    %w[inputs outputs].each do |field|
      error = assert_raises(SQLite3::ConstraintException) { database.execute("UPDATE transactions SET #{field} = '[]'") }
      assert_equal "Transaction content cannot change after creation", error.message
    end
    assert_equal [inputs, outputs], database.get_first_row("SELECT inputs, outputs FROM transactions")
    error = assert_raises(SQLite3::ConstraintException) { database.execute("UPDATE transactions SET block_id = ?", ["f" * 64]) }
    assert_equal "FOREIGN KEY constraint failed", error.message
    assert_nil database.get_first_value("SELECT block_id FROM transactions")
  ensure
    database&.close
  end

  private

  def with_step_one_tables
    TransactionStructureMigrationRecord.establish_connection(adapter: "sqlite3", database: ":memory:")
    TransactionStructureMigrationRecord.connection_pool.with_connection do |connection|
      %w[blocks transactions nodes candidate_blocks].each { |table| connection.create_table(table) }
      capture_io { UseHashIdentities.new.exec_migration(connection, :up) }
      yield connection
    end
  ensure
    TransactionStructureMigrationRecord.connection_pool.disconnect!
  end
end
