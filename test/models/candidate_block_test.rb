require "test_helper"

class CandidateBlockTest < ActiveSupport::TestCase
  test "stores a candidate with timestamps without creating a block or a header" do
    candidate = nil

    assert_no_difference ["Block.count", "Transaction.count"] do
      assert_difference "CandidateBlock.count", 1 do
        candidate = CandidateBlock.create!
      end
    end

    assert_equal candidate, CandidateBlock.find(candidate.id)
    assert_equal ["created_at", "id", "identity_seed", "updated_at"], CandidateBlock.column_names.sort
    assert_match(/\A[0-9a-f]{64}\z/, candidate.id)
    assert_not_nil candidate.created_at
    assert_not_nil candidate.updated_at
  end
end
