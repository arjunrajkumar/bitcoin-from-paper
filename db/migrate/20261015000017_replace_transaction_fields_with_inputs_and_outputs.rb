class ReplaceTransactionFieldsWithInputsAndOutputs < ActiveRecord::Migration[8.1]
  def up
    populated = %w[transactions blocks].select do |table|
      connection.select_value("SELECT COUNT(*) FROM #{table}").positive?
    end
    unless populated.empty?
      raise ActiveRecord::MigrationError, "Transaction structure migration requires empty tables: #{populated.join(', ')}"
    end

    drop_table :transactions
    create_table :transactions, id: :string, limit: 64, options: "WITHOUT ROWID" do |t|
      t.json :inputs, default: [], null: false
      t.json :outputs, default: [], null: false
      t.references :block, type: :string, foreign_key: true
      t.timestamps
    end
    execute <<~SQL
      CREATE TRIGGER transactions_immutable_content
      BEFORE UPDATE ON transactions
      WHEN OLD.id IS NOT NEW.id OR OLD.inputs IS NOT NEW.inputs OR OLD.outputs IS NOT NEW.outputs
      BEGIN
        SELECT RAISE(ABORT, 'Transaction content cannot change after creation');
      END
    SQL
    execute <<~SQL
      CREATE TRIGGER transactions_hash_format
      BEFORE INSERT ON transactions
      WHEN length(NEW.id) != 64 OR NEW.id GLOB '*[^0-9a-f]*'
      BEGIN
        SELECT RAISE(ABORT, 'Transaction id must be a lowercase 64-character hash');
      END
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Input and output lists cannot be converted back to the old transaction fields. Restore the pre-migration database backup."
  end
end
