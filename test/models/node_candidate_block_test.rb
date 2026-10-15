require "test_helper"

class NodeCandidateBlockTest < ActiveSupport::TestCase
  test "a node starts without a candidate block" do
    node = nil

    assert_no_difference ["Block.count", "CandidateBlock.count"] do
      node = Node.create!
    end

    assert_nil node.reload.candidate_block
  end

  test "each node can refer to its own candidate block" do
    first_block = CandidateBlock.create!
    second_block = CandidateBlock.create!
    first_node = Node.create!(candidate_block: first_block)
    second_node = Node.create!(candidate_block: second_block)

    assert_equal first_block.id, first_node.reload.candidate_block_id
    assert_equal first_block, first_node.candidate_block
    assert_equal second_block.id, second_node.reload.candidate_block_id
    assert_equal second_block, second_node.candidate_block
  end

  test "replacing or clearing a candidate changes only that node's reference" do
    first_block = CandidateBlock.create!
    second_block = CandidateBlock.create!
    other_block = CandidateBlock.create!
    node = Node.create!(candidate_block: first_block)
    other_node = Node.create!(candidate_block: other_block)

    assert_no_difference ["Block.count", "CandidateBlock.count"] do
      node.update!(candidate_block: second_block)
      assert_equal second_block, node.reload.candidate_block
      assert_equal other_block, other_node.reload.candidate_block

      node.update!(candidate_block: nil)
      assert_nil node.reload.candidate_block
      assert_nil node.candidate_block_id
    end

    assert_equal first_block, CandidateBlock.find(first_block.id)
    assert_equal second_block, CandidateBlock.find(second_block.id)
    assert_equal other_block, other_node.reload.candidate_block
  end

  test "a regular block cannot be assigned as a candidate block" do
    node = Node.create!
    block = Block.create!

    assert_raises(ActiveRecord::AssociationTypeMismatch) do
      node.update!(candidate_block: block)
    end

    assert_nil node.reload.candidate_block
  end

  test "the database requires a candidate block even if a regular block has that id" do
    node = Node.create!
    missing_candidate_id = CandidateBlock.maximum(:id).to_i + 1
    Block.create!(id: missing_candidate_id)

    assert_raises(ActiveRecord::InvalidForeignKey) do
      node.update_column(:candidate_block_id, missing_candidate_id)
    end

    assert_nil node.reload.candidate_block_id
  end
end
