class Transaction < ApplicationRecord
  belongs_to :block, optional: true

  validates :input_transaction_ids, presence: true, on: :create
  validates :public_key, presence: true, on: :create
  validates :receiver_output_value, numericality: true, on: :create
end
