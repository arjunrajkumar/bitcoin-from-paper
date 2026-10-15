require "test_helper"

class TransactionInputListTest < ActiveSupport::TestCase
  test "stores one input without changing the previous transaction" do
    previous = transactions(:first_previous)
    before = previous.attributes.deep_dup
    transaction = Transaction.new(transaction_attributes(previous_id: previous.id))
    assert_difference("Transaction.count", 1) { transaction.save! }
    assert_equal [previous.id], transaction.reload.inputs.map { |input| input.fetch("previous_transaction_id") }
    assert_equal before, previous.reload.attributes
  end

  test "stores three inputs in their supplied order" do
    previous = [transactions(:third_previous), transactions(:first_previous), transactions(:second_previous)]
    before = previous.map { |transaction| transaction.attributes.deep_dup }
    inputs = previous.map { |transaction| transaction_attributes(previous_id: transaction.id).fetch(:inputs).first }
    transaction = Transaction.new(transaction_attributes.merge(inputs: inputs))
    assert_difference("Transaction.count", 1) { transaction.save! }
    assert_equal previous.map(&:id), transaction.reload.inputs.map { |input| input.fetch("previous_transaction_id") }
    assert_equal before, previous.map { |record| record.reload.attributes }
  end

  test "stores repeated references until spending validation is implemented" do
    input = transaction_attributes(previous_id: transactions(:first_previous).id).fetch(:inputs).first
    transaction = Transaction.create!(transaction_attributes.merge(inputs: [input, input]))
    assert_equal 2, transaction.reload.inputs.length
    assert_equal transaction.inputs.first, transaction.inputs.last
  end

  test "failed creation leaves the previous transaction unchanged" do
    previous = transactions(:first_previous)
    before = previous.attributes.deep_dup
    transaction = Transaction.new(transaction_attributes(previous_id: previous.id, public_key: nil))
    assert_no_difference("Transaction.count") { assert_not transaction.save }
    assert_equal ["Outputs item 0 script_pub_key public_key must be a nonblank string"], transaction.errors.full_messages
    assert_equal before, previous.reload.attributes
  end
end
