require "test_helper"

class UnspentOutputTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    Transaction.delete_all
    Block.delete_all
  end

  test "validation alone leaves the set unchanged and first save adds each output" do
    source = prepare_unspent_transaction(values: ["5"])
    before = available_outputs
    transaction = Transaction.new(inputs: [input(source.id, 0)], outputs: [output("3", "alice"), output("2", "bob")])
    assert transaction.valid?
    assert_equal before, available_outputs
    assert transaction.save
    assert_equal [[transaction.id, 0], [transaction.id, 1]], available_outputs.keys.sort
    assert_equal ["output_index", "transaction_id"], UnspentOutput.column_names.sort
    assert_equal ["transaction_id", "output_index"], UnspentOutput.primary_key
    assert_equal [transaction.id, 1], UnspentOutput.find([transaction.id, 1]).id
    assert_equal({ "value" => "2.0", "script_pub_key" => { "operation" => "OP_CHECKSIG", "public_key" => "bob" } }, UnspentOutput.find([transaction.id, 1]).output)
  end

  test "all ordinary creation paths update the same persistent set" do
    creators.each_with_index do |create, index|
      source = prepare_unspent_transaction(values: ["2.125"])
      before = available_outputs
      transaction = create.call(inputs: [input(source.id, 0)], outputs: [output("0.00000001", "receiver-#{index}")])
      assert transaction.persisted?
      expected = before.except([source.id, 0]).merge([transaction.id, 0] => { "value" => "0.00000001", "script_pub_key" => { "operation" => "OP_CHECKSIG", "public_key" => "receiver-#{index}" } })
      assert_equal expected, available_outputs
      assert_equal [0], Transaction.find(transaction.id).unspent_outputs.pluck(:output_index)
    end
  end

  test "spending one output keeps its sibling and the complete transaction history" do
    source = prepare_unspent_transaction(values: ["3", "2"])
    before = source.reload.attributes.deep_dup
    later = Transaction.create!(inputs: [input(source.id, 1)], outputs: [output("1", "carol"), output("1", "bob-change")])
    assert_equal [[source.id, 0], [later.id, 0], [later.id, 1]].sort, available_outputs.keys.sort
    assert_equal [0], source.unspent_outputs.pluck(:output_index)
    assert_equal before, source.reload.attributes
    assert_equal 2, Transaction.count
  end

  test "multiple inputs remove only their exact references and new outputs can be spent next" do
    first = prepare_unspent_transaction(values: ["3", "2"])
    second = prepare_unspent_transaction(values: ["2.125"])
    combined = Transaction.create!(inputs: [input(first.id, 1), input(second.id, 0)], outputs: [output("4", "carol")])
    assert_equal [[first.id, 0], [combined.id, 0]].sort, available_outputs.keys.sort
    last = Transaction.create!(inputs: [input(combined.id, 0), input(first.id, 0)], outputs: [output("7", "dave")])
    assert_equal [[last.id, 0]], available_outputs.keys
    assert_empty first.unspent_outputs
    assert_empty second.unspent_outputs
    assert_empty combined.unspent_outputs
    assert_equal 4, Transaction.count
  end

  test "saving metadata assigning blocks and broadcasting do not restore spent outputs" do
    source = prepare_unspent_transaction(values: ["2.125"])
    later = Transaction.create!(transaction_attributes(previous_id: source.id, public_key: "later"))
    before = available_outputs
    source.save!
    source.touch
    source.update!(block: Block.create!, created_at: 1.day.ago)
    source.update!(block: nil)
    sender = Node.create!
    receiver = Node.create!
    2.times { sender.broadcast_transaction(source) }
    receiver.receive_transaction(later)
    assert_equal before, available_outputs
    assert_empty source.unspent_outputs
  end

  test "invalid creation through every path leaves history and available outputs unchanged" do
    source = prepare_unspent_transaction(values: ["2.125"])
    creators.each do |create|
      before = available_outputs
      assert_no_difference "Transaction.count" do
        begin
          invalid = create.call(inputs: [input(source.id, 0)], outputs: [output("invalid", "receiver")])
        rescue ActiveRecord::RecordInvalid => error
          invalid = error.record
        end
        assert_not invalid.persisted?
        assert_equal ["Outputs item 0 value must be a finite number"], invalid.errors.full_messages
      end
      assert_equal before, available_outputs
    end
  end

  test "duplicate creation and rejected content edits leave the set unchanged" do
    source = prepare_unspent_transaction(values: ["2.125"])
    later = Transaction.create!(transaction_attributes(previous_id: source.id, public_key: "later"))
    before = available_outputs
    assert_no_difference "Transaction.count" do
      assert_raises(ActiveRecord::RecordNotUnique) { Transaction.insert_all!([later.attributes]) }
      assert_not later.update(outputs: [output("9", "changed")])
      assert_equal ["Transaction content cannot change after creation"], later.errors.full_messages
      invalid = Transaction.new(transaction_attributes(previous_id: later.id, public_key: "wrong-id").merge(id: "f" * 64))
      assert_not invalid.save
      assert_equal ["Id must match the calculated hash"], invalid.errors.full_messages
    end
    assert_equal before, available_outputs
  end

  test "failure during output insertion rolls back input removals and earlier inserted outputs" do
    source = prepare_unspent_transaction(values: ["2.125"])
    block = Block.create!
    before = available_outputs
    original_block = block.attributes.deep_dup
    Transaction.connection.execute <<~SQL
      CREATE TEMP TRIGGER reject_second_unspent_output
      BEFORE INSERT ON unspent_outputs WHEN NEW.output_index = 1
      BEGIN
        SELECT RAISE(ABORT, 'Test output write failure');
      END;
    SQL
    assert_no_difference "Transaction.count" do
      error = assert_raises(ActiveRecord::StatementInvalid) do
        block.transactions.create!(inputs: [input(source.id, 0)], outputs: [output("1", "alice"), output("1", "bob")])
      end
      assert_equal "Test output write failure", error.cause.message
    end
    assert_equal before, available_outputs
    assert_equal original_block, block.reload.attributes
    assert_empty block.transactions
  ensure
    Transaction.connection.execute("DROP TRIGGER IF EXISTS reject_second_unspent_output")
  end

  test "a caller rollback restores both the transaction history and the set" do
    source = prepare_unspent_transaction(values: ["2.125"])
    before = available_outputs
    assert_no_difference "Transaction.count" do
      Transaction.transaction(requires_new: true) do
        Transaction.create!(transaction_attributes(previous_id: source.id, public_key: "later"))
        assert_not UnspentOutput.exists?(transaction_id: source.id, output_index: 0)
        raise ActiveRecord::Rollback
      end
    end
    assert_equal before, available_outputs
  end

  test "invalid spending cannot add new available outputs" do
    source = prepare_unspent_transaction(values: ["2.125"])
    repeated = input(source.id, 0)
    before = available_outputs
    first = Transaction.new(inputs: [repeated, repeated, input("f" * 64, 4_294_967_295)], outputs: [output("-1", "alice")])
    second = Transaction.new(inputs: [repeated], outputs: [output("1000", "bob")])
    assert_not first.save
    assert_equal ["Outputs item 0 value must not be negative"], first.errors.full_messages
    assert_not second.save
    assert_equal ["Outputs total value must not exceed total input value"], second.errors.full_messages
    assert_equal before, available_outputs
    assert_equal 1, Transaction.count
  end

  test "generated transaction sequences match an independent output map after every save" do
    random = Random.new(17102026)
    expected = {}
    boundaries = ["0", "-0", "0.00000001", "999999999999.99999999", "1.234567895"]
    36.times do |step|
      references = expected.keys.sample([expected.size, random.rand(1..3)].min, random: random)
      source = prepare_unspent_transaction(values: ["1000000000100"])
      references << [source.id, 0]
      inputs = references.map { |hash, position| input(hash, position) }
      values = Array.new([1, 2, 5].fetch(step % 3)) do |index|
        step < boundaries.length && index.zero? ? boundaries.fetch(step) : format("%d.%08d", random.rand(0..20), random.rand(0..99_999_999))
      end
      outputs = values.each_with_index.map { |value, index| output(value, "key-#{step}-#{index}") }
      transaction = Transaction.create!(inputs: inputs, outputs: outputs)
      references.each { |reference| expected.delete(reference) }
      values.each_with_index do |value, index|
        amount = BigDecimal(value).round(8)
        assert amount.finite?
        expected[[transaction.id, index]] = { "value" => amount.zero? ? "0.0" : amount.to_s("F"), "script_pub_key" => { "operation" => "OP_CHECKSIG", "public_key" => "key-#{step}-#{index}" } }
      end
      assert_equal expected, available_outputs, "UTXO set after transaction #{step}"
    end
  end

  test "deleting source history removes its own rows without restoring consumed inputs" do
    source = prepare_unspent_transaction(values: ["2.125"])
    later = Transaction.create!(transaction_attributes(previous_id: source.id, public_key: "later"))
    later.destroy!
    assert_empty available_outputs
    assert_equal 1, Transaction.count
    Transaction.delete_all
    assert_equal 0, UnspentOutput.count
  end

  private

  def available_outputs
    UnspentOutput.order(:transaction_id, :output_index).to_h { |entry| [[entry.transaction_id, entry.output_index], entry.output] }
  end

  def input(hash, index)
    { previous_transaction_id: hash, output_index: index, script_sig: "stored-proof" }
  end

  def output(value, key)
    { value: value, script_pub_key: { operation: "OP_CHECKSIG", public_key: key } }
  end

  def creators
    [
      ->(attributes) { Transaction.create(attributes) },
      ->(attributes) { Transaction.create!(attributes) },
      ->(attributes) { Transaction.new(attributes).tap(&:save) },
      ->(attributes) { Transaction.new(attributes).tap(&:save!) },
      ->(attributes) { Node.new.create_transaction(attributes) },
      ->(attributes) { Node.create!.create_transaction(attributes) },
      ->(attributes) { Block.create!.transactions.create!(attributes) }
    ]
  end
end
