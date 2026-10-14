class RemoveTotalInputValueFromTransactions < ActiveRecord::Migration[8.1]
  def change
    remove_column :transactions, :total_input_value, :decimal, precision: 20, scale: 8
  end
end
