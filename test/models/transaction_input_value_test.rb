require "test_helper"

class TransactionInputValueTest < ActiveSupport::TestCase
  test "calculates the total for one saved input without storing it" do
    transaction = build_transaction(input_transaction_ids: [transactions(:first_previous).id])

    assert_equal BigDecimal("5"), transaction.total_input_value
    transaction.save!
    assert_equal BigDecimal("5"), transaction.reload.total_input_value
    assert_not Transaction.column_names.include?("total_input_value")
  end

  test "adds the receiver values of all referenced transactions exactly" do
    values = ["0.10000001", "0.20000002", "0.30000003"]
    previous_transactions = [transactions(:first_previous), transactions(:second_previous), transactions(:third_previous)]
    previous_transactions.zip(values).each do |previous, value|
      previous.update!(receiver_output_value: value)
    end
    transaction = build_transaction(input_transaction_ids: previous_transactions.map(&:id), receiver_output_value: "0.60000006")

    assert_equal BigDecimal("0.60000006"), transaction.total_input_value
    assert transaction.save
    assert_empty transaction.errors.full_messages
  end

  test "uses current values and the current input list for each calculation" do
    previous = transactions(:first_previous)
    transaction = build_transaction(input_transaction_ids: [previous.id])
    assert_equal BigDecimal("5"), transaction.total_input_value

    previous.update!(receiver_output_value: "4.5")
    assert_equal BigDecimal("4.5"), transaction.total_input_value

    transaction.input_transaction_ids << transactions(:second_previous).id
    assert_equal BigDecimal("7.5"), transaction.total_input_value
  end

  test "counts each referenced transaction once when IDs are repeated" do
    previous_id = transactions(:first_previous).id
    transaction = build_transaction(input_transaction_ids: [previous_id, previous_id], receiver_output_value: "6")

    assert_equal BigDecimal("5"), transaction.total_input_value
    assert_not transaction.save
    assert_equal ["Receiver output value must be less than or equal to total input value"], transaction.errors.full_messages
  end

  test "rejects creation when a referenced receiver value is missing or stored as null" do
    previous = transactions(:first_previous)
    [nil, BigDecimal("NaN")].each do |value|
      previous.update!(receiver_output_value: value)
      transaction = build_transaction(input_transaction_ids: [previous.id])

      assert_nil previous.reload.receiver_output_value
      assert_nil transaction.total_input_value
      assert_not transaction.save
      assert_equal({ total_input_value: ["is not a number"] }, transaction.errors.to_hash)
    end
  end

  test "rejects creation when the calculated total is not finite" do
    previous = transactions(:first_previous)
    [BigDecimal("Infinity"), BigDecimal("-Infinity")].each do |value|
      previous.update!(receiver_output_value: value)
      transaction = build_transaction(input_transaction_ids: [previous.id])

      assert_not transaction.save
      assert_equal({ total_input_value: ["must be finite"] }, transaction.errors.to_hash)
    end
  end

  test "does not calculate a partial total when an input record is missing" do
    transaction = build_transaction(input_transaction_ids: [transactions(:first_previous).id, -1])

    assert_raises(ActiveRecord::RecordNotFound) { transaction.total_input_value }
    assert_no_difference "Transaction.count" do
      assert_raises(ActiveRecord::RecordNotFound) { transaction.save }
    end
  end

  private

  def build_transaction(**attributes)
    Transaction.new(public_key: "new-owner-public-key", receiver_output_value: "2", **attributes)
  end
end
