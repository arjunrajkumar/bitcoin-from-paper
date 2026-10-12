class CreateTransactions < ActiveRecord::Migration[8.1]
  def change
    create_table :transactions do |t|
      t.references :block, null: true, foreign_key: true
      t.timestamps
    end
  end
end
