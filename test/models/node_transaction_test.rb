require "test_helper"

class NodeTransactionTest < ActiveSupport::TestCase
  test "creates a transaction without broadcasting it" do
    sender = Node.create!
    Node.create!
    transaction = nil

    receipts = capture_receipts do
      assert_difference "Transaction.count", 1 do
        transaction = sender.create_transaction(transaction_attributes)
      end
    end

    assert transaction.persisted?
    assert_equal "receiver-public-key", transaction.reload.outputs.first.fetch("script_pub_key").fetch("public_key")
    assert_equal "sender-signature", transaction.inputs.first.fetch("script_sig")
    assert_equal "2.125", transaction.outputs.first.fetch("value")
    assert_equal transactions(:first_previous).id, transaction.inputs.first.fetch("previous_transaction_id")
    assert_equal 0, transaction.inputs.first.fetch("output_index")
    assert_nil transaction.block_id
    assert_equal [], receipts
  end

  test "creation does not require a saved node or a node transaction list" do
    sender = Node.new
    transaction = nil

    assert_no_difference "Node.count" do
      assert_difference "Transaction.count", 1 do
        transaction = sender.create_transaction(transaction_attributes)
      end
    end

    assert transaction.persisted?
    assert_not sender.respond_to?(:known_transactions)
  end

  test "creation keeps the existing transaction validation rules" do
    sender = Node.create!
    invalid_attributes = [
      [transaction_attributes(public_key: nil), "Outputs item 0 script_pub_key public_key must be a nonblank string"],
      [{ inputs: [] }, "Inputs must be a non-empty array"],
      [transaction_attributes(value: "not-a-number"), "Outputs item 0 value must be a finite number"]
    ]

    invalid_attributes.each do |attributes, expected_error|
      assert_no_difference "Transaction.count" do
        error = assert_raises(ActiveRecord::RecordInvalid) do
          sender.create_transaction(transaction_attributes.merge(attributes))
        end
        assert_equal [expected_error], error.record.errors.full_messages
      end
    end
  end

  test "broadcast delivers the same saved transaction to every other node" do
    sender = Node.create!
    receivers = Array.new(3) { Node.create! }
    transaction = sender.create_transaction(transaction_attributes)
    saved_attributes = transaction.attributes

    receipts = capture_receipts do
      assert_no_difference ["Transaction.count", "Block.count", "Node.count"] do
        sender.broadcast_transaction(transaction)
      end
    end

    assert_equal receivers.sort_by(&:id).map { |node| "Node #{node.id} received transaction #{transaction.id}" }, receipts
    assert_equal saved_attributes, transaction.reload.attributes
  end

  test "receiving reports each call without creating transaction copies" do
    receiver = Node.create!
    first = transactions(:first_previous)
    second = transactions(:second_previous)

    receipts = capture_receipts do
      assert_no_difference "Transaction.count" do
        receiver.receive_transaction(first)
        receiver.receive_transaction(second)
        Node.find(receiver.id).receive_transaction(first)
      end
    end

    assert_equal [
      "Node #{receiver.id} received transaction #{first.id}",
      "Node #{receiver.id} received transaction #{second.id}",
      "Node #{receiver.id} received transaction #{first.id}"
    ], receipts
  end

  test "broadcast can be repeated and can be relayed by a receiving node" do
    sender = Node.create!
    receiver = Node.create!
    transaction = sender.create_transaction(transaction_attributes)
    capture_receipts { sender.broadcast_transaction(transaction) }
    later_node = Node.create!

    receipts = capture_receipts do
      assert_no_difference "Transaction.count" do
        receiver.broadcast_transaction(transaction)
        sender.broadcast_transaction(transaction)
      end
    end

    expected_nodes = [sender, later_node].sort_by(&:id) + [receiver, later_node].sort_by(&:id)
    assert_equal expected_nodes.map { |node| "Node #{node.id} received transaction #{transaction.id}" }, receipts
  end

  test "a broadcast with no other nodes keeps the sender's transaction" do
    sender = Node.create!
    transaction = sender.create_transaction(transaction_attributes)

    receipts = capture_receipts do
      assert_no_difference ["Transaction.count", "Node.count"] do
        sender.broadcast_transaction(transaction)
      end
    end
    assert_equal [], receipts
    assert transaction.reload.persisted?
  end

  test "broadcasting one transaction does not broadcast another" do
    sender = Node.create!
    receiver = Node.create!
    first = sender.create_transaction(transaction_attributes)
    second = sender.create_transaction(transaction_attributes(previous_id: transactions(:second_previous).id, value: "3"))

    saved_second = second.attributes
    receipts = capture_receipts { sender.broadcast_transaction(first) }

    assert_equal ["Node #{receiver.id} received transaction #{first.id}"], receipts
    assert_equal saved_second, second.reload.attributes
  end

  private

  def capture_receipts
    output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(output)
    yield
    output.string.lines.map(&:chomp)
  ensure
    Rails.logger = original_logger
  end

  def transaction_attributes(**attributes)
    super(previous_id: transactions(:first_previous).id, **attributes)
  end
end
