class Node < ApplicationRecord
  include SeedIdentity

  belongs_to :candidate_block, optional: true

  def create_transaction(attributes)
    Transaction.create!(attributes)
  end

  def broadcast_transaction(transaction)
    Node.where.not(id: id).find_each do |node|
      node.receive_transaction(transaction)
    end
  end

  def receive_transaction(transaction)
    Rails.logger.info("Node #{id} received transaction #{transaction.id}")
  end

  def guess
    rand(ProtocolRules::PROOF_OF_WORK_NUMBER_RANGE)
  end

  private

  def calculate_id
    ContentHash.calculate("node", identity_seed)
  end
end
