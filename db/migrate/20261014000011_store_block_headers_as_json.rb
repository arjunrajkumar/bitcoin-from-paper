class StoreBlockHeadersAsJson < ActiveRecord::Migration[8.1]
  def up
    add_column :blocks, :header, :json,
      default: {transactions_hash: nil, previous_header_hash: nil}, null: false

    execute <<~SQL
      UPDATE blocks
      SET header = json_object(
        'transactions_hash', NULL,
        'previous_header_hash', previous_header_hash
      )
    SQL

    remove_foreign_key :blocks, column: :previous_header_hash
    remove_index :blocks, :previous_header_hash
    remove_column :blocks, :previous_header_hash

    # The JSON value is the single source for the database's chain reference.
    add_column :blocks, :previous_header_hash, :virtual,
      type: :string, as: "json_extract(header, '$.previous_header_hash')"
    add_index :blocks, :previous_header_hash
    add_foreign_key :blocks, :blocks, column: :previous_header_hash, primary_key: :header_hash
  end

  def down
    add_column :blocks, :restored_previous_header_hash, :string
    execute "UPDATE blocks SET restored_previous_header_hash = previous_header_hash"

    remove_foreign_key :blocks, column: :previous_header_hash
    remove_index :blocks, :previous_header_hash
    remove_column :blocks, :previous_header_hash
    rename_column :blocks, :restored_previous_header_hash, :previous_header_hash
    remove_column :blocks, :header

    add_index :blocks, :previous_header_hash
    add_foreign_key :blocks, :blocks, column: :previous_header_hash, primary_key: :header_hash
  end
end
