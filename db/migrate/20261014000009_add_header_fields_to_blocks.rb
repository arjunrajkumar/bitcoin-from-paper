class AddHeaderFieldsToBlocks < ActiveRecord::Migration[8.1]
  def change
    add_column :blocks, :header_hash, :string
    add_column :blocks, :timestamped_at, :datetime
    add_column :blocks, :previous_header_hash, :string
  end
end
