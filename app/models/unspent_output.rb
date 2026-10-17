class UnspentOutput < ApplicationRecord
  self.primary_key = [:transaction_id, :output_index]

  belongs_to :source_transaction, class_name: "Transaction", foreign_key: :transaction_id, inverse_of: :unspent_outputs

  def output
    source_transaction.outputs.fetch(output_index)
  end
end
