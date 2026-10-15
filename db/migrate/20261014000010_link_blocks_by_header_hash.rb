class LinkBlocksByHeaderHash < ActiveRecord::Migration[8.1]
  def change
    add_index :blocks, :header_hash, unique: true
    add_index :blocks, :previous_header_hash
    add_foreign_key :blocks, :blocks, column: :previous_header_hash, primary_key: :header_hash
  end
end
