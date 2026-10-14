class AddInputTransactionIdsToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :input_transaction_ids, :json, default: []
  end
end
