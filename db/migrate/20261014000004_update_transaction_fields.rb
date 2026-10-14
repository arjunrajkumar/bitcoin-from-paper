class UpdateTransactionFields < ActiveRecord::Migration[8.1]
  def change
    rename_column :transactions, :receiver_public_key, :public_key
    rename_column :transactions, :sender_digital_signature, :digital_signature
    add_column :transactions, :receiver_output_value, :decimal, precision: 20, scale: 8
  end
end
