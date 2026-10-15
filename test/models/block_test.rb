require "test_helper"
require "digest"
require "json"

class BlockTest < ActiveSupport::TestCase
  test "creates a block without assigned transactions" do
    block = Block.create!
    assert_empty block.reload.transactions
    assert_match(/\A[0-9a-f]{64}\z/, block.id)
  end

  test "keeps the previous hash inside the header and height separate from identity" do
    assert_equal %w[created_at header height id updated_at], Block.column_names.sort
    assert_equal ["transactions"], Block.reflections.keys
    assert_empty Block.connection.foreign_keys(:blocks)
    assert_equal :string, Block.type_for_attribute("id").type
    assert_equal :integer, Block.type_for_attribute("height").type
  end

  test "an unsaved block has no stored identity header time or height" do
    block = Block.new
    assert_nil block.id
    assert_nil block.height
    assert_nil block.created_at
    assert_equal({"transactions_hash" => nil, "created_at" => nil, "previous_header_hash" => nil}, block.header)
    assert_equal digest("block", nil, nil, nil), block.calculate_header_hash
    assert_nil block.id
  end

  test "records the block creation time and real transaction hash in its header" do
    travel_to Time.utc(2026, 10, 15, 10, 30) do
      block = Block.create!.reload
      expected_hash = digest("transactions", fixture_ids)
      assert_equal Time.utc(2026, 10, 15, 10, 30), block.created_at
      assert_equal({"transactions_hash" => expected_hash, "created_at" => "2026-10-15T10:30:00.000000Z", "previous_header_hash" => nil}, block.header)
      assert_equal expected_hash, block.calculate_transactions_hash
      assert_equal digest("block", expected_hash, "2026-10-15T10:30:00.000000Z", nil), block.id
    end
  end

  test "builds the header from potential transactions rather than assigned transactions" do
    recorded_time = Time.utc(2026, 10, 15, 10, 30, 0, 123456)
    potential = transactions(:first_previous)
    assigned = transactions(:second_previous)
    block = Block.new(transactions: [assigned], created_at: recorded_time, header: { transactions_hash: "old" })
    block.define_singleton_method(:potential_transactions) { [potential] }
    block.save!
    expected_hash = digest("transactions", [potential.id])
    assert_equal expected_hash, block.calculate_transactions_hash
    assert_equal({"transactions_hash" => expected_hash, "created_at" => "2026-10-15T10:30:00.123456Z", "previous_header_hash" => nil}, block.reload.header)
    assert_equal block, assigned.reload.block
    assert_nil potential.reload.block
  end

  test "later transactions and calculations do not rebuild the saved header or identity" do
    block = Block.create!
    stored = block.reload.attributes
    later = Transaction.create!(transaction_attributes(previous_id: transactions(:first_previous).id, value: "1", public_key: "later-owner"))
    block.save!
    assert_equal digest("transactions", (fixture_ids + [later.id]).sort), block.calculate_transactions_hash
    assert_equal stored, block.reload.attributes
    assert_equal block.id, block.calculate_header_hash
    assert_empty block.transactions
    assert_nil later.reload.block
  end

  test "potential transactions include every stored transaction in hash order" do
    block = Block.create!
    block.transactions << [transactions(:first_previous), transactions(:second_previous)]
    other = Block.create!
    other.transactions << transactions(:third_previous)
    assert_equal fixture_ids, Block.new.potential_transactions.map(&:id)
    assert_equal digest("transactions", fixture_ids), block.reload.calculate_transactions_hash
    block.transactions.load
    assert_equal digest("transactions", fixture_ids), block.calculate_transactions_hash
    assert_equal other, transactions(:third_previous).reload.block
  end

  test "an empty transaction list has a fixed hash" do
    Transaction.delete_all
    block = Block.create!(created_at: Time.utc(2026, 10, 15, 10, 30))
    assert_empty block.potential_transactions
    assert_equal "fdf7242ec324913675e399e38c040e613079dbb965d54c35048138ba76926dbc", block.transactions_hash
    assert_equal({"transactions_hash" => block.transactions_hash, "created_at" => "2026-10-15T10:30:00.000000Z", "previous_header_hash" => nil}, block.reload.header)
  end

  test "saved header contents cannot change through accessors or replacement" do
    block = Block.create!
    stored = block.reload.attributes.deep_dup
    [{ transactions_hash: "a" * 64 }, { previous_header_hash: "b" * 64 }, { header: { "transactions_hash" => "c" * 64 } }].each do |change|
      assert_not block.update(change)
      assert_equal ["Block content cannot change after creation"], block.errors.full_messages
      assert_equal stored, block.reload.attributes
    end
    block.header["created_at"] = "2000-01-01T00:00:00.000000Z"
    assert_not block.save
    assert_equal ["Block content cannot change after creation"], block.errors.full_messages
    assert_equal stored, block.reload.attributes
  end

  test "changing Rails metadata does not change the saved header time or hash" do
    block = Block.create!(created_at: Time.utc(2026, 10, 15, 10, 30))
    original_id, original_header = block.id, block.header.deep_dup
    block.update!(created_at: Time.utc(2026, 10, 16), updated_at: Time.utc(2026, 10, 17))
    assert_equal original_id, block.reload.id
    assert_equal original_header, block.header
    assert_equal "2026-10-15T10:30:00.000000Z", block.header.fetch("created_at")
    assert_equal Time.utc(2026, 10, 17), block.updated_at
  end

  test "links three blocks by hashes and keeps last-saved order despite timestamps" do
    first = Block.create!(created_at: Time.utc(2026, 10, 15))
    second = Block.create!(created_at: Time.utc(2026, 10, 14))
    third = Block.create!(created_at: Time.utc(2026, 10, 16))
    assert_nil first.previous_header_hash
    assert_equal first.id, second.reload.previous_header_hash
    assert_equal second.id, third.reload.previous_header_hash
    assert_equal [0, 1, 2], [first, second, third].map(&:height)
    [first, second, third].each { |block| assert_equal block.id, block.calculate_header_hash }
    assert_equal first, Block.find(second.previous_header_hash)
    assert_equal second, Block.find(third.previous_header_hash)
  end

  test "equal timestamps still produce a sequential chain with distinct hashes" do
    travel_to Time.utc(2026, 10, 15) do
      blocks = Array.new(5) { Block.create! }
      assert_equal [0, 1, 2, 3, 4], blocks.map(&:height)
      assert_equal 5, blocks.map(&:id).uniq.length
      blocks.each_cons(2) { |first, second| assert_equal first.id, second.previous_header_hash }
      assert_equal 1, blocks.map(&:created_at).uniq.length
    end
  end

  test "a duplicate block hash fails at the database boundary" do
    block = Block.create!
    assert_no_difference "Block.count" do
      assert_raises(ActiveRecord::RecordNotUnique) { Block.insert_all!([block.attributes.merge("height" => 50)]) }
    end
    assert_equal 0, block.reload.height
  end

  test "a transaction may be created without a block" do
    transaction = Transaction.create!(transaction_attributes(previous_id: transactions(:first_previous).id, value: "2", public_key: "receiver"))
    assert_nil transaction.reload.block
    assert_nil transaction.block_id
  end

  test "both association creation paths use the block hash" do
    block = Block.create!
    first = block.transactions.create!(transaction_attributes(previous_id: transactions(:first_previous).id, value: "2", public_key: "first-receiver"))
    second = Transaction.create!(transaction_attributes(previous_id: transactions(:second_previous).id, value: "1", public_key: "second-receiver").merge(block: block))
    assert_equal [first.id, second.id].sort, block.reload.transactions.order(:id).pluck(:id)
    [first, second].each do |transaction|
      assert_equal block, transaction.reload.block
      assert_equal block.id, transaction.block_id
    end
  end

  test "an existing transaction can move between blocks or leave its block" do
    transaction = transactions(:first_previous)
    original_id = transaction.id
    first, second = Block.create!, Block.create!
    first.transactions << transaction
    assert_equal first, transaction.reload.block
    transaction.update!(block: second)
    assert_equal second, transaction.reload.block
    assert_empty first.reload.transactions
    assert_equal [original_id], second.reload.transactions.pluck(:id)
    transaction.update!(block: nil)
    assert_nil transaction.reload.block
    assert_nil transaction.block_id
    assert_equal original_id, transaction.id
    assert_empty second.reload.transactions
  end

  test "missing block hashes and deletion of referenced blocks fail" do
    transaction = transactions(:first_previous)
    assert_raises(ActiveRecord::InvalidForeignKey) { transaction.update_column(:block_id, "f" * 64) }
    assert_nil transaction.reload.block_id
    block = Block.create!
    transaction.update!(block: block)
    assert_raises(ActiveRecord::InvalidForeignKey) { block.delete }
    assert_equal block.id, transaction.reload.block_id
    assert_equal block, Block.find(block.id)
  end

  private

  def fixture_ids
    transactions(:first_previous, :second_previous, :third_previous).map(&:id).sort
  end

  def digest(*values)
    Digest::SHA256.hexdigest(Digest::SHA256.digest(JSON.generate(values)))
  end
end
