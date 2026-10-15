require "test_helper"

class BlockTest < ActiveSupport::TestCase
  test "creates a block without transactions" do
    block = Block.create!

    assert_empty block.reload.transactions
  end

  test "keeps block links inside the header without separate hash columns" do
    assert_equal ["created_at", "header", "id", "updated_at"], Block.column_names.sort
    assert_equal ["transactions"], Block.reflections.keys
    assert_empty Block.connection.foreign_keys(:blocks)
  end

  test "an unsaved block has no creation time or transaction hash" do
    block = Block.new

    assert_nil block.created_at
    assert_nil block.transactions_hash
    assert_nil block.previous_header_hash
    assert_equal({"transactions_hash" => nil, "created_at" => nil, "previous_header_hash" => nil}, block.header)
    assert_equal({"transactions_hash" => nil, "created_at" => nil, "previous_header_hash" => nil}, block.calculate_header_hash)
  end

  test "records the block creation time in its header" do
    travel_to Time.utc(2026, 10, 15, 10, 30, 0) do
      block = Block.create!.reload
      expected_ids = transactions(:first_previous, :second_previous, :third_previous).map(&:id).sort

      assert_equal Time.utc(2026, 10, 15, 10, 30, 0), block.created_at
      assert_equal({"transactions_hash" => expected_ids, "created_at" => "2026-10-15T10:30:00.000000Z", "previous_header_hash" => nil}, block.header)
      assert_equal expected_ids, block.calculate_transactions_hash
    end
  end

  test "builds the header from potential transactions rather than assigned transactions" do
    recorded_time = Time.utc(2026, 10, 15, 10, 30, 0, 123456)
    potential_transaction = transactions(:first_previous)
    assigned_transaction = transactions(:second_previous)
    block = Block.new(
      transactions: [assigned_transaction],
      created_at: recorded_time,
      header: {transactions_hash: "T1", created_at: "2000-01-01T00:00:00.000000Z"}
    )
    block.define_singleton_method(:potential_transactions) { [potential_transaction] }
    block.save!
    block.reload

    assert_equal recorded_time, block.created_at
    assert_equal [potential_transaction.id], block.calculate_transactions_hash
    assert_equal({"transactions_hash" => [potential_transaction.id], "created_at" => "2026-10-15T10:30:00.123456Z", "previous_header_hash" => nil}, block.header)
    assert_equal block, assigned_transaction.reload.block
    assert_nil potential_transaction.reload.block
  end

  test "records current potential transactions without rebuilding when more become available" do
    expected_ids = transactions(:first_previous, :second_previous, :third_previous).map(&:id).sort
    block = Block.create!(created_at: Time.utc(2026, 10, 15, 10, 30, 0))

    expected_header = {"transactions_hash" => expected_ids, "created_at" => "2026-10-15T10:30:00.000000Z", "previous_header_hash" => nil}
    assert_equal expected_header, block.reload.header
    assert_empty block.transactions

    later_transaction = Transaction.create!(
      public_key: "later-receiver-public-key",
      receiver_output_value: "1",
      input_transaction_ids: [transactions(:first_previous).id]
    )
    block.save!

    assert_equal expected_header, block.reload.header
    assert_equal (expected_ids + [later_transaction.id]).sort, block.calculate_transactions_hash
    assert_empty block.transactions
    assert_nil later_transaction.reload.block
  end

  test "the hash placeholders leave stored values unchanged" do
    recorded_time = Time.utc(2026, 10, 15, 10, 30, 0)
    block = Block.create!(created_at: recorded_time, transactions: [transactions(:first_previous)])
    stored_values = block.reload.attributes
    expected_ids = transactions(:first_previous, :second_previous, :third_previous).map(&:id).sort

    assert_equal expected_ids, block.calculate_transactions_hash
    assert_equal({"transactions_hash" => expected_ids, "created_at" => "2026-10-15T10:30:00.000000Z", "previous_header_hash" => nil}, block.calculate_header_hash)
    assert_equal stored_values, block.reload.attributes
  end

  test "potential transactions currently include every stored transaction" do
    block = Block.create!
    block.transactions << [transactions(:first_previous), transactions(:second_previous)]
    another_block = Block.create!
    another_block.transactions << transactions(:third_previous)
    expected_ids = transactions(:first_previous, :second_previous, :third_previous).map(&:id).sort

    assert_equal expected_ids, Block.new.potential_transactions.map(&:id)
    assert_equal expected_ids, block.reload.calculate_transactions_hash
    block.transactions.load
    assert_equal expected_ids, block.calculate_transactions_hash
    assert_equal another_block, transactions(:third_previous).reload.block
  end

  test "an empty transaction store produces empty candidates and an empty header input" do
    Transaction.delete_all
    block = Block.create!(created_at: Time.utc(2026, 10, 15, 10, 30, 0))

    assert_empty block.potential_transactions
    assert_equal [], block.calculate_transactions_hash
    assert_equal({"transactions_hash" => [], "created_at" => "2026-10-15T10:30:00.000000Z", "previous_header_hash" => nil}, block.reload.header)
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
    assert_equal({"transactions_hash" => "T2", "created_at" => "2026-10-15T10:30:00.000000Z", "previous_header_hash" => nil}, block.header)

    travel_to Time.utc(2026, 10, 17) do
      assert_equal({"transactions_hash" => "T2", "created_at" => "2026-10-15T10:30:00.000000Z", "previous_header_hash" => nil}, block.calculate_header_hash)
    end
    assert_equal Time.utc(2026, 10, 16, 11, 0, 0), block.reload.updated_at
  end

  test "replacing the header does not add the creation time again" do
    block = Block.create!(created_at: Time.utc(2026, 10, 15, 10, 30, 0), transactions_hash: "T1")

    block.update!(header: {transactions_hash: "T2"})

    assert_equal({"transactions_hash" => "T2"}, block.reload.header)
    assert_equal Time.utc(2026, 10, 15, 10, 30, 0), block.created_at
  end

  test "links three blocks through their complete headers using the hash placeholder" do
    expected_ids = transactions(:first_previous, :second_previous, :third_previous).map(&:id).sort
    first = Block.create!(created_at: Time.utc(2026, 10, 15, 10, 30, 0))
    second = Block.create!(created_at: Time.utc(2026, 10, 15, 10, 40, 0))
    third = Block.create!(created_at: Time.utc(2026, 10, 15, 10, 50, 0))
    first_header = {"transactions_hash" => expected_ids, "created_at" => "2026-10-15T10:30:00.000000Z", "previous_header_hash" => nil}
    second_header = {"transactions_hash" => expected_ids, "created_at" => "2026-10-15T10:40:00.000000Z", "previous_header_hash" => first_header}
    third_header = {"transactions_hash" => expected_ids, "created_at" => "2026-10-15T10:50:00.000000Z", "previous_header_hash" => second_header}

    assert_equal first_header, first.reload.header
    assert_equal second_header, second.reload.header
    assert_equal third_header, third.reload.header
    assert_equal first_header, second.previous_header_hash
    assert_equal second_header, third.previous_header_hash
    assert_equal third_header, third.calculate_header_hash
  end

  test "extends the last saved block even when creation times are out of order" do
    first = Block.create!(created_at: Time.utc(2026, 10, 15))
    second = Block.create!(created_at: Time.utc(2026, 10, 14))
    third = Block.create!(created_at: Time.utc(2026, 10, 16))

    assert_equal first.header, second.reload.previous_header_hash
    assert_equal second.header, third.reload.previous_header_hash
    refute_equal first.header, third.previous_header_hash
  end

  test "saved links stay unchanged when an earlier block changes or a later block arrives" do
    first = Block.create!(created_at: Time.utc(2026, 10, 15, 10, 30, 0))
    second = Block.create!(created_at: Time.utc(2026, 10, 15, 10, 40, 0))
    original_first_header = first.header.deep_dup

    first.update!(transactions_hash: "changed")
    third = Block.create!(created_at: Time.utc(2026, 10, 15, 10, 50, 0))
    second.update!(transactions_hash: "updated-second")

    assert_equal original_first_header, second.reload.previous_header_hash
    assert_equal original_first_header, third.reload.previous_header_hash.fetch("previous_header_hash")
    refute_equal first.reload.header, second.previous_header_hash
    refute_equal second.header, third.previous_header_hash
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
