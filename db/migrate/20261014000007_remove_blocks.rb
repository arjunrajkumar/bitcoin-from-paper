class RemoveBlocks < ActiveRecord::Migration[8.1]
  def change
    remove_reference :transactions, :block, foreign_key: true

    drop_table :blocks do |t|
      t.timestamps
    end
  end
end
