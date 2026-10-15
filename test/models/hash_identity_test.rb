require "test_helper"
require "digest"
require "json"

class HashIdentityTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    Node.delete_all
    Transaction.delete_all
    CandidateBlock.delete_all
    Block.delete_all
  end

  test "all four domain tables use hash primary keys without integer row aliases" do
    [Transaction, Block, Node, CandidateBlock].each do |model|
      assert_equal "id", model.primary_key
      assert_equal :string, model.type_for_attribute("id").type
      sql = model.connection.select_value("SELECT sql FROM sqlite_master WHERE name = '#{model.table_name}'")
      assert_includes sql, "WITHOUT ROWID"
      error = assert_raises(ActiveRecord::StatementInvalid) { model.connection.select_all("SELECT rowid FROM #{model.table_name}") }
      assert_includes error.message, "no such column: rowid"
    end
    assert_equal :string, Transaction.type_for_attribute("block_id").type
    assert_equal :string, Node.type_for_attribute("candidate_block_id").type
  end

  test "transaction and block hashes match independent fixed vectors" do
    transaction = Transaction.create!(transaction_attributes)
    assert_equal "ab37591adbe53d5dd47c342ec54ac422ebaa50cdbb34da2cd4fea3f212c44c9d", transaction.reload.id
    block = Block.create!(created_at: Time.utc(2026, 10, 15, 10, 30))
    assert_equal "2fd75ced97893587046b0ea5248ebbda55cdc64fe5553e7f359278903639af40", block.transactions_hash
    assert_equal "7348e59197762b6ec0d5e8ebb5db8916609d8247d7e01c1704f614194f1a9134", block.reload.id
    assert_equal block.id, block.calculate_header_hash
    assert_equal 0, block.height
    assert_nil block.previous_header_hash
  end

  test "seed hashes have separate type labels and persist across reloads" do
    node = Node.create!(identity_seed: "00" * 32)
    candidate = CandidateBlock.create!(identity_seed: "00" * 32)
    assert_equal "a9d91c94f377c7de34456d2ab2b7576aad9fa55fa3186143cf90e56d4fbcda88", node.reload.id
    assert_equal "618d3b203b9c295a1f61dac64fefa5360496fc59422f9742b761314a985ff433", candidate.reload.id
    assert_equal "00" * 32, node.identity_seed
    assert_equal "00" * 32, candidate.identity_seed
    node.update!(candidate_block: candidate)
    assert_equal candidate.id, node.reload.candidate_block_id
    assert_equal candidate, node.candidate_block
  end

  test "new nodes and candidates get distinct seeds even at the same time" do
    travel_to Time.utc(2026, 10, 15) do
      [Node, CandidateBlock].each do |model|
        records = Array.new(20) { model.create! }
        assert_equal 20, records.map(&:id).uniq.length
        assert_equal 20, records.map(&:identity_seed).uniq.length
        records.each do |record|
          assert_match(/\A[0-9a-f]{64}\z/, record.identity_seed)
          assert_match(/\A[0-9a-f]{64}\z/, record.reload.id)
        end
      end
    end
  end

  test "duplicates fail without adding a record" do
    Transaction.create!(transaction_attributes)
    assert_no_difference "Transaction.count" do
      assert_raises(ActiveRecord::RecordNotUnique) { Transaction.create!(transaction_attributes.merge(created_at: 1.day.ago)) }
    end
    [Node, CandidateBlock].each do |model|
      model.create!(identity_seed: "00" * 32)
      assert_no_difference "#{model.name}.count" do
        assert_raises(ActiveRecord::RecordNotUnique) { model.create!(identity_seed: "00" * 32) }
      end
    end
  end

  test "supplied identities cannot disagree with their contents" do
    [Transaction.new(transaction_attributes), Node.new, CandidateBlock.new, Block.new].each do |record|
      record.id = "f" * 64
      assert_no_difference "#{record.class.name}.count" do
        assert_not record.save
      end
      assert_equal ["Id must match the calculated hash"], record.errors.full_messages
    end
  end

  test "content changes fail atomically through normal and direct updates" do
    transaction = Transaction.create!(transaction_attributes)
    block = Block.create!
    node = Node.create!
    candidate = CandidateBlock.create!
    changes = [
      [transaction, { public_key: "changed", block_id: block.id }],
      [transaction, { digital_signature: "changed" }],
      [transaction, { input_count: 2 }],
      [transaction, { receiver_output_value: "3" }],
      [transaction, { input_transaction_ids: ["b" * 64] }],
      [transaction, { id: "f" * 64 }],
      [block, { header: { "transactions_hash" => "f" * 64 } }],
      [block, { height: 5 }],
      [block, { id: "f" * 64 }],
      [node, { identity_seed: "ff" * 32, candidate_block_id: candidate.id }],
      [node, { id: "f" * 64 }],
      [candidate, { identity_seed: "ff" * 32 }],
      [candidate, { id: "f" * 64 }]
    ]
    changes.each do |record, attributes|
      before = record.reload.attributes
      assert_not record.update(attributes)
      assert_equal ["#{record.class.name} content cannot change after creation"], record.errors.full_messages
      record.id = before.fetch("id")
      assert_equal before, record.reload.attributes
      error = assert_raises(ActiveRecord::StatementInvalid) { record.update_columns(attributes) }
      assert_includes error.message, "#{record.class.name} content cannot change after creation"
      record.id = before.fetch("id")
      assert_equal before, record.reload.attributes
    end
  end

  test "metadata and optional assignments do not change identities" do
    transaction = Transaction.create!(transaction_attributes)
    original_id = transaction.id
    block = Block.create!
    transaction.update!(block: block, created_at: 1.day.ago)
    assert_equal original_id, transaction.reload.id
    assert_equal block, transaction.block
    transaction.update!(block: nil)
    assert_equal original_id, transaction.reload.id
    node = Node.create!
    node_id = node.id
    candidates = Array.new(2) { CandidateBlock.create! }
    (candidates + [nil]).each do |candidate|
      node.update!(candidate_block: candidate)
      assert_equal node_id, node.reload.id
      candidate ? assert_equal(candidate.id, node.candidate_block_id) : assert_nil(node.candidate_block_id)
    end
  end

  test "hash references reject malformed values but retain later-step spending cases" do
    [nil, [], "a" * 64, [1], ["abc"], ["A" * 64], [nil]].each do |inputs|
      transaction = Transaction.new(transaction_attributes.merge(input_transaction_ids: inputs))
      assert_not transaction.save
      expected = inputs.nil? || inputs == [] ? "Input transaction ids can't be blank" : "Input transaction ids must be an array of lowercase 64-character hashes"
      assert_equal [expected], transaction.errors.full_messages
    end
    transaction = Transaction.create!(transaction_attributes.merge(input_transaction_ids: ["b" * 64, "b" * 64], receiver_output_value: "-1"))
    assert_equal ["b" * 64, "b" * 64], transaction.reload.input_transaction_ids
    assert_equal BigDecimal("-1"), transaction.receiver_output_value
  end

  test "invalid identity seeds fail without creating records" do
    [Node, CandidateBlock].each do |model|
      ["", "a", "A" * 64, "g" * 64].each do |seed|
        record = model.new(identity_seed: seed)
        assert_not record.save
        assert_equal ["Identity seed must be 64 lowercase hexadecimal characters"], record.errors.full_messages
      end
    end
  end

  test "nonfinite output values cannot enter the hash format" do
    [BigDecimal("NaN"), BigDecimal("Infinity"), BigDecimal("-Infinity")].each do |value|
      transaction = Transaction.new(transaction_attributes.merge(receiver_output_value: value))
      assert_not transaction.save
      assert_equal ["Receiver output value must be finite"], transaction.errors.full_messages
    end
  end

  test "generated decimal contents match a separate digest oracle after reload" do
    random = Random.new(15102026)
    values = ["0", "-0", "0.00000001", "-0.00000001", "999999999999.99999999", "1.234567895"]
    values += Array.new(40) { format("%d.%08d", random.rand(-1000..1000), random.rand(0..99_999_999)) }
    values.each_with_index do |value, index|
      attributes = transaction_attributes.merge(receiver_output_value: value, public_key: "key-#{index}-£", input_count: index)
      transaction = Transaction.create!(attributes).reload
      amount = transaction.receiver_output_value
      assert_equal BigDecimal(value).round(8), amount
      decimal = amount.zero? ? "0.0" : amount.to_s("F")
      payload = ["transaction", ["a" * 64], index, decimal, "key-#{index}-£", "sender-signature"]
      expected = Digest::SHA256.hexdigest(Digest::SHA256.digest(JSON.generate(payload)))
      assert_equal expected, transaction.id, "Hash must match persisted content for #{value}"
      assert amount.finite?
    end
  end

  test "each transaction field and ordered input list affects the hash" do
    base = Transaction.create!(transaction_attributes)
    variants = [
      { input_transaction_ids: ["b" * 64] }, { input_count: 2 },
      { receiver_output_value: "2.126" }, { public_key: "other" }, { digital_signature: "other" },
      { digital_signature: nil }, { input_count: nil },
      { input_transaction_ids: ["a" * 64, "b" * 64] },
      { input_transaction_ids: ["b" * 64, "a" * 64] }
    ].map { |attributes| Transaction.create!(transaction_attributes.merge(attributes)) }
    assert_equal 10, ([base] + variants).map(&:id).uniq.length
    same = Transaction.new(transaction_attributes.merge(receiver_output_value: "2.12500000"))
    assert_raises(ActiveRecord::RecordNotUnique) { same.save! }
  end

  private

  def transaction_attributes
    { input_transaction_ids: ["a" * 64], input_count: 1, receiver_output_value: "2.125", public_key: "receiver-public-key", digital_signature: "sender-signature" }
  end
end
