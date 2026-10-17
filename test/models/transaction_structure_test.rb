require "test_helper"

class TransactionStructureTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    Transaction.delete_all
    Block.delete_all
    prepare_unspent_transaction(values: ["5"], id: "a" * 64)
    prepare_unspent_transaction(values: ["1", "5"], id: "b" * 64)
  end

  test "stores ordered input proofs and output conditions without old columns" do
    transaction = Transaction.create!(attributes_for_transaction)
    assert_equal ["block_id", "created_at", "id", "inputs", "outputs", "updated_at"], Transaction.column_names.sort
    assert_equal [{ "previous_transaction_id" => "a" * 64, "output_index" => 0, "script_sig" => "sender-signature" }], transaction.reload.inputs
    assert_equal [{ "value" => "2.125", "script_pub_key" => { "operation" => "OP_CHECKSIG", "public_key" => "receiver-public-key" } }], transaction.outputs
  end

  test "two later transactions can reference different outputs from the same transaction" do
    source = Transaction.create!(attributes_for_transaction.merge(outputs: [output("3", "alice"), output("2", "bob")]))
    before = source.attributes.deep_dup
    first = Transaction.create!(inputs: [input(source.id, 0, "alice-proof")], outputs: [output("3", "carol")])
    second = Transaction.create!(inputs: [input(source.id, 1, "bob-proof")], outputs: [output("2", "dave")])
    [first, second].each_with_index do |transaction, position|
      reference = transaction.reload.inputs.fetch(0)
      assert_equal source.id, reference.fetch("previous_transaction_id")
      assert_equal position, reference.fetch("output_index")
      previous_output = Transaction.find(reference.fetch("previous_transaction_id")).outputs.fetch(reference.fetch("output_index"))
      assert_equal ["3.0", "2.0"].fetch(position), previous_output.fetch("value")
      assert_equal ["alice", "bob"].fetch(position), previous_output.fetch("script_pub_key").fetch("public_key")
    end
    assert_equal before, source.reload.attributes
  end

  test "hashes ignore object key order but include input and output list order" do
    inputs = [input("a" * 64, 0, "first-proof"), input("b" * 64, 1, "second-proof")]
    outputs = [output("1", "alice"), output("2", "bob")]
    hashes = []
    [
      { inputs: inputs, outputs: outputs },
      { inputs: inputs.reverse, outputs: outputs },
      { inputs: inputs, outputs: outputs.reverse },
      { inputs: inputs.map { |item| item.to_a.reverse.to_h }, outputs: outputs.map { |item| item.to_a.reverse.to_h } }
    ].each do |attributes|
      Transaction.transaction(requires_new: true) do
        hashes << Transaction.create!(attributes).reload.id
        raise ActiveRecord::Rollback
      end
    end
    assert_equal 3, hashes.first(3).uniq.length
    assert_equal hashes.first, hashes.last
  end

  test "saved nested lists cannot change through model or direct writes" do
    transaction = Transaction.create!(attributes_for_transaction)
    before = transaction.reload.attributes.deep_dup
    [{ inputs: [input("a" * 64, 1, "other-proof")] }, { outputs: [output("3", "other-key")] }].each do |change|
      assert_not transaction.update(change)
      assert_equal ["Transaction content cannot change after creation"], transaction.errors.full_messages
      assert_equal before, transaction.reload.attributes
      error = assert_raises(ActiveRecord::StatementInvalid) { transaction.update_columns(change) }
      assert_includes error.message, "Transaction content cannot change after creation"
      assert_equal before, transaction.reload.attributes
    end
  end

  test "unsupported operations fail without writing any part of the transaction" do
    transaction = Transaction.new(attributes_for_transaction.merge(outputs: [output("1", "alice"), { value: "2", script_pub_key: { operation: "OP_CHECKLOCKTIMEVERIFY", public_key: "bob" } }]))
    assert_no_difference "Transaction.count" do
      assert_not transaction.save
    end
    assert_equal ["Outputs item 1 script_pub_key operation must be OP_CHECKSIG"], transaction.errors.full_messages
  end

  test "a structurally valid reference still needs an available output" do
    reference = input("f" * 64, 12, "")
    transaction = Transaction.new(inputs: [reference], outputs: [output("1", "alice")])
    assert_no_difference("Transaction.count") { assert_not transaction.save }
    assert_equal ["Inputs item 0 references a missing or spent output"], transaction.errors.full_messages
    assert_not Transaction.exists?("f" * 64)
  end

  test "invalid nested creation cannot partially change a block or source transaction" do
    source = Transaction.create!(attributes_for_transaction)
    block = Block.create!
    original_source = source.reload.attributes.deep_dup
    original_block = block.reload.attributes.deep_dup
    attributes = { inputs: [input(source.id, 0, "proof")], outputs: [output("1", "alice"), output("invalid", "bob")] }
    assert_no_difference ["Transaction.count", "Block.count"] do
      error = assert_raises(ActiveRecord::RecordInvalid) { block.transactions.create!(attributes) }
      assert_equal ["Outputs item 1 value must be a finite number"], error.record.errors.full_messages
    end
    assert_equal original_source, source.reload.attributes
    assert_equal original_block, block.reload.attributes
    assert_empty block.transactions
  end

  test "generated lists match an independent hash oracle and preserve every output" do
    random = Random.new(15102027)
    [1, 2, 5].product([1, 2, 5]).each_with_index do |(input_count, output_count), case_index|
      sources = Array.new(input_count) { prepare_unspent_transaction(values: ["100", "100"]) }
      inputs = sources.each_with_index.map { |source, index| input(source.id, index % 2, "proof-#{case_index}-#{index}") }
      outputs = Array.new(output_count) { |index| output(format("%d.%08d", random.rand(0..10), random.rand(0..99_999_999)), "key-#{case_index}-#{index}") }
      expected_outputs = outputs.map { |item| [BigDecimal(item.fetch(:value)).to_s("F"), "OP_CHECKSIG", item.fetch(:script_pub_key).fetch(:public_key)] }
      expected_inputs = inputs.map { |item| [item.fetch(:previous_transaction_id), item.fetch(:output_index), item.fetch(:script_sig)] }
      payload = JSON.generate(["transaction", expected_inputs, expected_outputs])
      expected_hash = Digest::SHA256.hexdigest(Digest::SHA256.digest(payload))
      transaction = Transaction.create!(inputs: inputs, outputs: outputs).reload
      assert_equal expected_hash, transaction.id
      assert_equal expected_outputs.map(&:first), transaction.outputs.map { |item| item.fetch("value") }
      assert_equal expected_inputs, transaction.inputs.map { |item| [item.fetch("previous_transaction_id"), item.fetch("output_index"), item.fetch("script_sig")] }
    end
  end

  private

  def attributes_for_transaction
    { inputs: [input("a" * 64, 0, "sender-signature")], outputs: [output("2.125", "receiver-public-key")] }
  end

  def input(hash, position, signature)
    { previous_transaction_id: hash, output_index: position, script_sig: signature }
  end

  def output(value, key)
    { value: value, script_pub_key: { operation: "OP_CHECKSIG", public_key: key } }
  end
end
