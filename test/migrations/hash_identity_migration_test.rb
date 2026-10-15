require "test_helper"
require "sqlite3"
require Rails.root.join("db/migrate/20261015000016_use_hash_identities")

class HashIdentityMigrationRecord < ActiveRecord::Base
  self.abstract_class = true
end

class HashIdentityMigrationTest < ActiveSupport::TestCase
  self.fixture_table_names = []
  self.use_transactional_tests = false

  test "migration refuses each populated table before changing the database" do
    %w[blocks transactions nodes candidate_blocks].each do |populated|
      with_old_tables do |connection|
        connection.execute("INSERT INTO #{populated} (id) VALUES (17)")
        schema = connection.select_rows("SELECT name, sql FROM sqlite_master ORDER BY name")
        error = assert_raises(ActiveRecord::MigrationError) do
          quietly { UseHashIdentities.new.exec_migration(connection, :up) }
        end
        assert_equal "Hash identity migration requires empty tables: #{populated}", error.message.strip
        assert_equal schema, connection.select_rows("SELECT name, sql FROM sqlite_master ORDER BY name")
        assert_equal 17, connection.select_value("SELECT id FROM #{populated}")
      end
    end
  end

  test "migration replaces empty tables and refuses a lossy rollback" do
    with_old_tables do |connection|
      quietly { UseHashIdentities.new.exec_migration(connection, :up) }
      %w[blocks transactions nodes candidate_blocks].each do |table|
        assert_includes connection.select_value("SELECT sql FROM sqlite_master WHERE name = '#{table}'"), "WITHOUT ROWID"
        assert_equal :string, connection.columns(table).find { |column| column.name == "id" }.type
      end
      error = assert_raises(ActiveRecord::IrreversibleMigration) do
        quietly { UseHashIdentities.new.exec_migration(connection, :down) }
      end
      assert_equal "Hash identities cannot be converted back to integer identities. Restore the pre-migration database backup.", error.message.strip
    end
  end

  test "the saved SQL schema restores hash keys triggers and foreign keys" do
    database = SQLite3::Database.new(":memory:")
    database.execute("PRAGMA foreign_keys = ON")
    database.execute_batch(File.read(Rails.root.join("db/structure.sql")))
    assert_equal 8, database.get_first_value("SELECT count(*) FROM sqlite_master WHERE type = 'trigger'")
    database.execute("INSERT INTO candidate_blocks (id, identity_seed, created_at, updated_at) VALUES (?, ?, ?, ?)", ["a" * 64, "b" * 64, "2026-10-15", "2026-10-15"])
    error = assert_raises(SQLite3::ConstraintException) { database.execute("UPDATE candidate_blocks SET identity_seed = ?", ["c" * 64]) }
    assert_equal "CandidateBlock content cannot change after creation", error.message
    assert_equal "b" * 64, database.get_first_value("SELECT identity_seed FROM candidate_blocks")
    error = assert_raises(SQLite3::ConstraintException) do
      database.execute("INSERT INTO nodes (id, identity_seed, candidate_block_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?)", ["b" * 64, "c" * 64, "f" * 64, "2026-10-15", "2026-10-15"])
    end
    assert_equal "FOREIGN KEY constraint failed", error.message
    error = assert_raises(SQLite3::ConstraintException) do
      database.execute("INSERT INTO candidate_blocks (id, identity_seed, created_at, updated_at) VALUES (?, ?, ?, ?)", ["17", "b" * 64, "2026-10-15", "2026-10-15"])
    end
    assert_equal "CandidateBlock id must be a lowercase 64-character hash", error.message
    %w[blocks transactions nodes candidate_blocks].each do |table|
      error = assert_raises(SQLite3::SQLException) { database.execute("SELECT rowid FROM #{table}") }
      assert_includes error.message, "no such column: rowid"
    end
  ensure
    database&.close
  end

  private

  def with_old_tables
    HashIdentityMigrationRecord.establish_connection(adapter: "sqlite3", database: ":memory:")
    HashIdentityMigrationRecord.connection_pool.with_connection do |connection|
      %w[blocks transactions nodes candidate_blocks].each { |table| connection.create_table(table) }
      yield connection
    end
  ensure
    HashIdentityMigrationRecord.connection_pool.disconnect!
  end

  def quietly
    capture_io { yield }
  end
end
