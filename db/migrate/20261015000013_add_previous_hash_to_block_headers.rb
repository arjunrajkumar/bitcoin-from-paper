class AddPreviousHashToBlockHeaders < ActiveRecord::Migration[8.1]
  def change
    change_column_default :blocks, :header,
      from: {transactions_hash: nil, created_at: nil},
      to: {transactions_hash: nil, created_at: nil, previous_header_hash: nil}
  end
end
