class Block < ApplicationRecord
  store_accessor :header, :transactions_hash

  has_many :transactions

  before_create :record_header_creation_time

  def calculate_transactions_hash
    # Hashing needs to be added later.
    transactions.pluck(:id)
  end

  def calculate_header_hash
    # Hashing needs to be added later.
    header
  end

  private

  def record_header_creation_time
    header["created_at"] = created_at&.utc&.iso8601(6)
  end
end
