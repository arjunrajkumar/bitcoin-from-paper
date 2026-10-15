class CandidateBlock < ApplicationRecord
  include SeedIdentity

  private

  def calculate_id
    ContentHash.calculate("candidate-block", identity_seed)
  end
end
