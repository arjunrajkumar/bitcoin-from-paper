class Node < ApplicationRecord
  def guess
    rand(ProtocolRules::PROOF_OF_WORK_NUMBER_RANGE)
  end
end
