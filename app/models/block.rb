class Block < ApplicationRecord
  store_accessor :header, :transactions_hash, :previous_header_hash

  has_many :transactions

  before_create :build_header
  include HashIdentity

  def potential_transactions
    # Receiving transactions from the network will be added later.
    Transaction.order(:id)
  end

  def calculate_transactions_hash
    ContentHash.calculate("transactions", potential_transactions.map(&:id))
  end

  def calculate_header_hash
    ContentHash.calculate("block", transactions_hash, header["created_at"], previous_header_hash)
  end

  private

  def build_header
    previous = Block.order(:height).last
    self.height = previous ? previous.height + 1 : 0
    self.header = {
      "transactions_hash" => calculate_transactions_hash,
      "created_at" => created_at.utc.iso8601(6),
      "previous_header_hash" => previous&.id
    }
  end

  def calculate_id
    calculate_header_hash
  end

  def identity_attributes
    %w[header height]
  end
end
