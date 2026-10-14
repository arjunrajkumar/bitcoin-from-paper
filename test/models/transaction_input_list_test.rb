require "test_helper"

class TransactionInputListTest < ActiveSupport::TestCase
  test "stores one input ID without changing the previous transaction" do
    previous = transactions(:first_previous)
    previous_attributes = previous.attributes
    transaction = build_transaction(input_transaction_ids: [previous.id])

    assert_difference "Transaction.count", 1 do
      transaction.save!
    end

    assert_equal [previous.id], transaction.reload.input_transaction_ids
    assert_equal previous_attributes, previous.reload.attributes
  end

  test "stores three input IDs in their supplied order" do
    previous_transactions = [transactions(:third_previous), transactions(:first_previous), transactions(:second_previous)]
    previous_attributes = previous_transactions.map(&:attributes)
    previous_ids = previous_transactions.map(&:id)
    transaction = build_transaction(input_transaction_ids: previous_ids)

    assert_difference "Transaction.count", 1 do
      transaction.save!
    end

    assert_equal previous_ids, transaction.reload.input_transaction_ids
    assert_equal previous_attributes, previous_transactions.map { |previous| previous.reload.attributes }
  end

  test "stores the supplied list without removing repeated IDs" do
    previous_id = transactions(:first_previous).id
    transaction = build_transaction(input_transaction_ids: [previous_id, previous_id])
    transaction.save!

    assert_equal [previous_id, previous_id], transaction.reload.input_transaction_ids
  end

  test "requires at least one input ID on creation" do
    [{}, { input_transaction_ids: nil }, { input_transaction_ids: [] }].each do |attributes|
      transaction = build_transaction(**attributes)

      assert_no_difference "Transaction.count" do
        assert_not transaction.save
      end

      assert_equal ["Input transaction ids can't be blank"], transaction.errors.full_messages
    end
  end

  test "failed creation leaves the previous transaction unchanged" do
    previous = transactions(:first_previous)
    previous_attributes = previous.attributes
    transaction = build_transaction(public_key: nil, input_transaction_ids: [previous.id])

    assert_no_difference "Transaction.count" do
      assert_not transaction.save
    end

    assert_equal ["Public key can't be blank"], transaction.errors.full_messages
    assert_equal previous_attributes, previous.reload.attributes
  end

  private

  def build_transaction(**attributes)
    Transaction.new(public_key: "new-owner-public-key", receiver_output_value: "2", **attributes)
  end
end
