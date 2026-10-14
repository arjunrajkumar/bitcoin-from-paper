class AddInputCountAndTotalInputValueToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :input_count, :integer
    add_column :transactions, :total_input_value, :decimal, precision: 20, scale: 8
  end
end
