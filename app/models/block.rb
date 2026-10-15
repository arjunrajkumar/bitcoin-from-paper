class Block < ApplicationRecord
  store_accessor :header, :transactions_hash

  has_many :transactions

  before_create :build_header

  def potential_transactions
    # Receiving transactions from the network will be added later.
    Transaction.order(:id)
  end

  def calculate_transactions_hash
    # Hashing needs to be added later.
    potential_transactions.map(&:id)
  end

  def calculate_header_hash
    # Hashing needs to be added later.
    header
  end

  private

  def build_header
    header["transactions_hash"] = calculate_transactions_hash
    header["created_at"] = created_at&.utc&.iso8601(6)
  end
end
