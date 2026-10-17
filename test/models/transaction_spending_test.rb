require "test_helper"

class TransactionSpendingTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    Transaction.delete_all
    Block.delete_all
    @source = prepare_unspent_transaction(values: ["3", "2"])
  end

  test "a partial spend keeps the sibling output and source history" do
    original = @source.attributes.deep_dup
    payment = Transaction.create!(inputs: [input(@source.id, 1)], outputs: [output("1.5", "carol"), output("0.5", "bob")])
    assert_equal [[@source.id, 0], [payment.id, 0], [payment.id, 1]].sort, available_pairs
    assert_equal ["1.5", "0.5"], payment.reload.outputs.map { |item| item.fetch("value") }
    assert_equal original, @source.reload.attributes
  end

  test "different outputs of one transaction and outputs of different transactions can be combined" do
    other = prepare_unspent_transaction(values: ["0.25"])
    payment = Transaction.create!(inputs: [input(@source.id, 1), input(other.id, 0), input(@source.id, 0)], outputs: [output("5.25")])
    assert_equal [[payment.id, 0]], available_pairs
    assert_equal "5.25", payment.reload.outputs.first.fetch("value")
  end

  test "every creation path accepts exact value and a positive fee" do
    creators.each_with_index do |create, index|
      ["2", "1.99999999"].each do |value|
        source = prepare_unspent_transaction(values: ["2"])
        payment = create.call(transaction_attributes(previous_id: source.id, value: value, public_key: "receiver-#{index}"))
        assert payment.persisted?
        assert_equal BigDecimal(value), BigDecimal(payment.reload.outputs.first.fetch("value"))
        assert_not UnspentOutput.exists?(transaction_id: source.id, output_index: 0)
        assert UnspentOutput.exists?(transaction_id: payment.id, output_index: 0)
      end
    end
  end

  test "all spending failures leave history and the set unchanged through every creation path" do
    spent = prepare_unspent_transaction(values: ["1"])
    Transaction.create!(transaction_attributes(previous_id: spent.id, value: "1"))
    duplicate = input(@source.id, 1)
    cases = [
      [{ inputs: [duplicate, duplicate.merge(script_sig: "different-proof")], outputs: [output("4")] }, "Inputs item 1 repeats a previous output"],
      [{ inputs: [duplicate], outputs: [output("-1")] }, "Outputs item 0 value must not be negative"],
      [{ inputs: [input("a" * 64, 0)], outputs: [output("1")] }, "Inputs item 0 references a missing or spent output"],
      [{ inputs: [input(@source.id, 2)], outputs: [output("1")] }, "Inputs item 0 references a missing or spent output"],
      [{ inputs: [input(spent.id, 0)], outputs: [output("1")] }, "Inputs item 0 references a missing or spent output"],
      [{ inputs: [duplicate], outputs: [output("2.00000001")] }, "Outputs total value must not exceed total input value"]
    ]
    creators.each do |create|
      cases.each do |attributes, message|
        before = stored_state
        begin
          rejected = create.call(attributes)
        rescue ActiveRecord::RecordInvalid => error
          rejected = error.record
        end
        assert_not rejected.persisted?, message
        assert_equal [message], rejected.errors.full_messages
        assert_equal before, stored_state
      end
    end
  end

  test "duplicate detection uses the reference pair rather than proof or list position" do
    references = [input(@source.id, 0), input(@source.id, 1), input(@source.id, 0, "other-proof")]
    assert_rejected({ inputs: references, outputs: [output("1")] }, "Inputs item 2 repeats a previous output")
  end

  test "an unavailable later input cannot consume the earlier available input" do
    assert_rejected({ inputs: [input(@source.id, 0), input("e" * 64, 4_294_967_295)], outputs: [output("1")] }, "Inputs item 1 references a missing or spent output")
  end

  test "negative values remain invalid even if eight-place rounding would erase the sign" do
    ["-1", "-0.00000001", "-0.000000001", "-1e-100"].each do |value|
      assert_rejected({ inputs: [input(@source.id, 0)], outputs: [output("1"), output(value)] }, "Outputs item 1 value must not be negative")
    end
  end

  test "zero signed zero and positive rounding retain the existing decimal rule" do
    [["0", "0.0"], ["-0", "0.0"], ["0.000000001", "0.0"], ["0.000000005", "0.00000001"]].each do |value, expected|
      source = prepare_unspent_transaction(values: ["0.00000001"])
      payment = Transaction.create!(transaction_attributes(previous_id: source.id, value: value))
      assert_equal expected, payment.reload.outputs.first.fetch("value")
    end
    zero = prepare_unspent_transaction(values: ["0"])
    assert_rejected(transaction_attributes(previous_id: zero.id, value: "0.00000001"), "Outputs total value must not exceed total input value")
    assert Transaction.create!(transaction_attributes(previous_id: zero.id, value: "0")).persisted?
  end

  test "exact decimal totals allow a fee but never an extra smallest unit" do
    source = prepare_unspent_transaction(values: ["0.1", "0.2"])
    attributes = { inputs: [input(source.id, 0), input(source.id, 1)], outputs: [output("0.30000001")] }
    assert_rejected(attributes, "Outputs total value must not exceed total input value")
    payment = Transaction.create!(attributes.merge(outputs: [output("0.3")]))
    assert_equal "0.3", payment.reload.outputs.first.fetch("value")
  end

  test "validation is read only and saving rechecks a previously valid candidate" do
    first = Transaction.new(transaction_attributes(previous_id: @source.id, output_index: 1, value: "2", public_key: "first"))
    second = Transaction.new(transaction_attributes(previous_id: @source.id, output_index: 1, value: "2", public_key: "second"))
    before = stored_state
    2.times { assert first.valid?; assert second.valid? }
    assert_equal before, stored_state
    first.save!
    assert_rejected(second.attributes.slice("inputs", "outputs"), "Inputs item 0 references a missing or spent output")
    assert_not second.save
    assert_equal ["Inputs item 0 references a missing or spent output"], second.errors.full_messages
  end

  test "a failed second removal rolls back the first removal and new history" do
    Transaction.connection.execute <<~SQL
      CREATE TEMP TRIGGER leave_second_output
      BEFORE DELETE ON unspent_outputs WHEN OLD.transaction_id = '#{@source.id}' AND OLD.output_index = 1
      BEGIN
        SELECT RAISE(IGNORE);
      END;
    SQL
    assert_rejected({ inputs: [input(@source.id, 0), input(@source.id, 1)], outputs: [output("5")] }, "Inputs item 1 references a missing or spent output")
    before = stored_state
    error = assert_raises(ActiveRecord::RecordInvalid) do
      Transaction.create!(inputs: [input(@source.id, 0), input(@source.id, 1)], outputs: [output("5")])
    end
    assert_equal ["Inputs item 1 references a missing or spent output"], error.record.errors.full_messages
    assert_equal before, stored_state
  ensure
    Transaction.connection.execute("DROP TRIGGER IF EXISTS leave_second_output")
  end

  test "generated amounts preserve exact balance boundaries across input and output counts" do
    random = Random.new(17102027)
    [1, 2, 5].product([1, 2, 5]).each do |input_count, output_count|
      units = Array.new(input_count) { random.rand(1..100_000_000_000) }
      source = prepare_unspent_transaction(values: units.map { |amount| decimal_units(amount) })
      references = units.each_index.map { |index| input(source.id, index) }
      total = units.sum
      [-1, 0, 1].each do |difference|
        value = total + difference
        parts = Array.new(output_count, value / output_count)
        parts[-1] += value % output_count
        attributes = { inputs: references, outputs: parts.map { |amount| output(decimal_units(amount)) } }
        if difference.positive?
          assert_rejected(attributes, "Outputs total value must not exceed total input value")
        else
          Transaction.transaction(requires_new: true) do
            payment = Transaction.create!(attributes)
            assert_equal parts.map { |amount| Rational(amount, 100_000_000) }, payment.reload.outputs.map { |item| Rational(item.fetch("value")) }
            assert_equal value, payment.outputs.sum { |item| (Rational(item.fetch("value")) * 100_000_000).to_i }
            raise ActiveRecord::Rollback
          end
        end
      end
    end
  end

  test "a caller can continue its transaction after a failed input removal without partial spending" do
    Transaction.connection.execute <<~SQL
      CREATE TEMP TRIGGER refuse_second_removal
      BEFORE DELETE ON unspent_outputs WHEN OLD.transaction_id = '#{@source.id}' AND OLD.output_index = 1
      BEGIN
        SELECT RAISE(IGNORE);
      END;
    SQL
    Transaction.transaction(requires_new: true) do
      assert_rejected({ inputs: [input(@source.id, 0), input(@source.id, 1)], outputs: [output("5")] }, "Inputs item 1 references a missing or spent output")
      Transaction.connection.execute("DROP TRIGGER refuse_second_removal")
      assert Transaction.create!(transaction_attributes(previous_id: @source.id, value: "3")).persisted?
    end
    assert_equal 2, Transaction.count
  ensure
    Transaction.connection.execute("DROP TRIGGER IF EXISTS refuse_second_removal")
  end

  test "a caller can rescue an output write failure without retaining a partial payment" do
    Transaction.connection.execute <<~SQL
      CREATE TEMP TRIGGER refuse_second_insertion
      BEFORE INSERT ON unspent_outputs WHEN NEW.output_index = 1
      BEGIN
        SELECT RAISE(ABORT, 'Test output write failure');
      END;
    SQL
    Transaction.transaction(requires_new: true) do
      before = stored_state
      error = assert_raises(ActiveRecord::StatementInvalid) do
        Transaction.create!(inputs: [input(@source.id, 0)], outputs: [output("1"), output("2")])
      end
      assert_equal "Test output write failure", error.cause.message
      assert_equal before, stored_state
      Transaction.connection.execute("DROP TRIGGER refuse_second_insertion")
      assert Transaction.create!(transaction_attributes(previous_id: @source.id, value: "3")).persisted?
    end
    assert_equal 2, Transaction.count
  ensure
    Transaction.connection.execute("DROP TRIGGER IF EXISTS refuse_second_insertion")
  end

  private

  def input(hash, index, proof = "stored-proof")
    { previous_transaction_id: hash, output_index: index, script_sig: proof }
  end

  def output(value, key = "receiver")
    { value: value, script_pub_key: { operation: "OP_CHECKSIG", public_key: key } }
  end

  def decimal_units(units)
    format("%d.%08d", units / 100_000_000, units % 100_000_000)
  end

  def available_pairs
    UnspentOutput.order(:transaction_id, :output_index).pluck(:transaction_id, :output_index)
  end

  def stored_state
    [Transaction.order(:id).map(&:attributes), available_pairs]
  end

  def assert_rejected(attributes, message)
    before = stored_state
    transaction = Transaction.new(attributes)
    assert_not transaction.save
    assert_not transaction.persisted?
    assert_equal [message], transaction.errors.full_messages
    assert_equal before, stored_state
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
