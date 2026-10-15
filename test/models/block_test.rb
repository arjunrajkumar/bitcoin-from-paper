require "test_helper"

class BlockTest < ActiveSupport::TestCase
  test "creates a block without transactions" do
    block = Block.create!

    assert_empty block.reload.transactions
  end

  test "stores only the current block and its header" do
    assert_equal ["created_at", "header", "id", "updated_at"], Block.column_names.sort
    assert_equal ["transactions"], Block.reflections.keys
    assert_empty Block.connection.foreign_keys(:blocks)
  end

  test "an unsaved block has no creation time or transaction hash" do
    block = Block.new

    assert_nil block.created_at
    assert_nil block.transactions_hash
    assert_equal({"transactions_hash" => nil, "created_at" => nil}, block.header)
    assert_equal [], block.calculate_transactions_hash
    assert_equal({"transactions_hash" => nil, "created_at" => nil}, block.calculate_header_hash)
  end

  test "records the block creation time in its header" do
    travel_to Time.utc(2026, 10, 15, 10, 30, 0) do
      block = Block.create!.reload

      assert_equal Time.utc(2026, 10, 15, 10, 30, 0), block.created_at
      assert_equal({"transactions_hash" => nil, "created_at" => "2026-10-15T10:30:00.000000Z"}, block.header)
      assert_equal [], block.calculate_transactions_hash
    end
  end

  test "uses the block creation time when a supplied header has a different time" do
    recorded_time = Time.utc(2026, 10, 15, 10, 30, 0, 123456)
    block = Block.create!(
      created_at: recorded_time,
      header: {transactions_hash: "T1", created_at: "2000-01-01T00:00:00.000000Z"}
    ).reload

    assert_equal recorded_time, block.created_at
    assert_equal "T1", block.transactions_hash
    assert_equal({"transactions_hash" => "T1", "created_at" => "2026-10-15T10:30:00.123456Z"}, block.header)
  end

  test "the hash placeholders leave stored values unchanged" do
    recorded_time = Time.utc(2026, 10, 15, 10, 30, 0)
    block = Block.create!(created_at: recorded_time, transactions_hash: "T1")
    block.transactions << transactions(:first_previous)
    stored_values = block.reload.attributes

    assert_equal [transactions(:first_previous).id], block.calculate_transactions_hash
    assert_equal({"transactions_hash" => "T1", "created_at" => "2026-10-15T10:30:00.000000Z"}, block.calculate_header_hash)
    assert_equal stored_values, block.reload.attributes
  end

  test "returns only the IDs of transactions in this block" do
    block = Block.create!
    block.transactions << [transactions(:first_previous), transactions(:second_previous)]
    another_block = Block.create!
    another_block.transactions << transactions(:third_previous)
    expected_ids = [transactions(:first_previous).id, transactions(:second_previous).id].sort

    assert_equal expected_ids, block.reload.calculate_transactions_hash.sort
    block.transactions.load
    assert_equal expected_ids, block.calculate_transactions_hash.sort
  end

  test "later updates and calculations keep the original creation time" do
    block = travel_to Time.utc(2026, 10, 15, 10, 30, 0) do
      Block.create!(transactions_hash: "T1")
    end

    travel_to Time.utc(2026, 10, 16, 11, 0, 0) do
      block.update!(transactions_hash: "T2")
    end
    block.reload

    assert_equal Time.utc(2026, 10, 15, 10, 30, 0), block.created_at
    assert_equal Time.utc(2026, 10, 16, 11, 0, 0), block.updated_at
    assert_equal({"transactions_hash" => "T2", "created_at" => "2026-10-15T10:30:00.000000Z"}, block.header)

    travel_to Time.utc(2026, 10, 17) do
      assert_equal({"transactions_hash" => "T2", "created_at" => "2026-10-15T10:30:00.000000Z"}, block.calculate_header_hash)
    end
    assert_equal Time.utc(2026, 10, 16, 11, 0, 0), block.reload.updated_at
  end

  test "replacing the header does not add the creation time again" do
    block = Block.create!(created_at: Time.utc(2026, 10, 15, 10, 30, 0), transactions_hash: "T1")

    block.update!(header: {transactions_hash: "T2"})

    assert_equal({"transactions_hash" => "T2"}, block.reload.header)
    assert_equal Time.utc(2026, 10, 15, 10, 30, 0), block.created_at
  end

  test "creates a transaction without a block" do
    transaction = Transaction.create!(
      public_key: "receiver-public-key",
      receiver_output_value: "2",
      input_transaction_ids: [transactions(:first_previous).id]
    )

    assert_nil transaction.reload.block
    assert_nil transaction.block_id
  end

  test "a block contains multiple transactions" do
    block = Block.create!
    first = block.transactions.create!(
      public_key: "first-receiver-public-key",
      receiver_output_value: "2",
      input_transaction_ids: [transactions(:first_previous).id]
    )
    second = Transaction.create!(
      block: block,
      public_key: "second-receiver-public-key",
      receiver_output_value: "1",
      input_transaction_ids: [transactions(:second_previous).id]
    )

    assert_equal [first.id, second.id].sort, block.reload.transactions.order(:id).pluck(:id)
    assert_equal block, first.reload.block
    assert_equal block, second.reload.block
  end

  test "an existing transaction belongs to at most one block" do
    transaction = transactions(:first_previous)
    first_block = Block.create!
    second_block = Block.create!

    first_block.transactions << transaction
    assert_equal first_block, transaction.reload.block

    transaction.update!(block: second_block)
    assert_equal second_block, transaction.reload.block
    assert_empty first_block.reload.transactions
    assert_equal [transaction.id], second_block.reload.transactions.pluck(:id)

    transaction.update!(block: nil)
    assert_nil transaction.reload.block
    assert_nil transaction.block_id
    assert_empty second_block.reload.transactions
  end
end
