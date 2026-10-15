class UseHashIdentities < ActiveRecord::Migration[8.1]
  def up
    populated = %w[blocks transactions nodes candidate_blocks].select do |table|
      connection.select_value("SELECT COUNT(*) FROM #{table}").positive?
    end
    unless populated.empty?
      raise ActiveRecord::MigrationError, "Hash identity migration requires empty tables: #{populated.join(', ')}"
    end

    drop_table :nodes
    drop_table :transactions
    drop_table :candidate_blocks
    drop_table :blocks

    create_table :blocks, id: :string, limit: 64, options: "WITHOUT ROWID" do |t|
      t.integer :height, null: false, index: { unique: true }
      t.json :header, default: { transactions_hash: nil, created_at: nil, previous_header_hash: nil }, null: false
      t.timestamps
      t.check_constraint "height >= 0", name: "block_height_nonnegative"
    end

    create_table :transactions, id: :string, limit: 64, options: "WITHOUT ROWID" do |t|
      t.text :public_key
      t.text :digital_signature
      t.integer :input_count
      t.string :receiver_output_value
      t.json :input_transaction_ids, default: []
      t.references :block, type: :string, foreign_key: true
      t.timestamps
    end

    create_table :candidate_blocks, id: :string, limit: 64, options: "WITHOUT ROWID" do |t|
      t.string :identity_seed, limit: 64, null: false
      t.timestamps
    end

    create_table :nodes, id: :string, limit: 64, options: "WITHOUT ROWID" do |t|
      t.string :identity_seed, limit: 64, null: false
      t.references :candidate_block, type: :string, foreign_key: true
      t.timestamps
    end

    immutable_content :transactions, "Transaction", %w[id input_transaction_ids input_count receiver_output_value public_key digital_signature]
    immutable_content :blocks, "Block", %w[id header height]
    immutable_content :nodes, "Node", %w[id identity_seed]
    immutable_content :candidate_blocks, "CandidateBlock", %w[id identity_seed]
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Hash identities cannot be converted back to integer identities. Restore the pre-migration database backup."
  end

  private

  def immutable_content(table, model, fields)
    # SQL guards also cover update_columns, update_all and raw SQL writes.
    condition = fields.map { |field| "OLD.#{field} IS NOT NEW.#{field}" }.join(" OR ")
    execute <<~SQL
      CREATE TRIGGER #{table}_immutable_content
      BEFORE UPDATE ON #{table}
      WHEN #{condition}
      BEGIN
        SELECT RAISE(ABORT, '#{model} content cannot change after creation');
      END
    SQL
    execute <<~SQL
      CREATE TRIGGER #{table}_hash_format
      BEFORE INSERT ON #{table}
      WHEN length(NEW.id) != 64 OR NEW.id GLOB '*[^0-9a-f]*'
      BEGIN
        SELECT RAISE(ABORT, '#{model} id must be a lowercase 64-character hash');
      END
    SQL
  end
end
