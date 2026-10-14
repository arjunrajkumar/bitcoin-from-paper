class AddReceiverPublicKeyAndSenderDigitalSignatureToTransactions < ActiveRecord::Migration[8.1]
  def change
    add_column :transactions, :receiver_public_key, :text
    add_column :transactions, :sender_digital_signature, :text
  end
end
