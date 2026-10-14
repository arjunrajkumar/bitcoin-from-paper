class Transaction < ApplicationRecord
  belongs_to :block, optional: true

  validates :input_transaction_ids, presence: true, on: :create
  validates :public_key, presence: true, on: :create
  validates :receiver_output_value, numericality: true, on: :create

  def total_input_value
    values = Transaction.find(input_transaction_ids).map(&:receiver_output_value)
    return if values.any?(&:nil?)

    values.sum(BigDecimal("0"))
  end
end
