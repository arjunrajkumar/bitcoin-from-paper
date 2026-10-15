class AddBlocksToTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :blocks do |t|
      t.timestamps
    end

    add_reference :transactions, :block, null: true, foreign_key: true
  end
end
