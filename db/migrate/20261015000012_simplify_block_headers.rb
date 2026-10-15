class SimplifyBlockHeaders < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :blocks, column: :previous_header_hash
    remove_index :blocks, :previous_header_hash
    remove_index :blocks, :header_hash
    remove_columns :blocks, :previous_header_hash, :header_hash, :timestamped_at

    change_column_default :blocks, :header,
      from: {transactions_hash: nil, previous_header_hash: nil},
      to: {transactions_hash: nil, created_at: nil}

    block_model = Class.new(ActiveRecord::Base) do
      self.table_name = "blocks"
    end

    block_model.find_each do |block|
      block.update_columns(header: block.header.except("previous_header_hash").merge(
        "created_at" => block.created_at.utc.iso8601(6)
      ))
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "The removed block hashes and timestamped_at values cannot be restored."
  end
end
