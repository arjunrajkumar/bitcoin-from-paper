require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  test "stores input counts" do
    [10, 0, 1].each do |count|
      transaction = Transaction.create!(public_key: "receiver-public-key", input_count: count, receiver_output_value: "2", input_transaction_ids: [transactions(:first_previous).id])

      assert_equal count, transaction.reload.input_count
    end
  end

  test "leaves the input count unset until supplied" do
    transaction = Transaction.create!(public_key: "receiver-public-key", receiver_output_value: "2", input_transaction_ids: [transactions(:first_previous).id])

    assert_nil transaction.reload.input_count
  end

  test "stores the public key and digital signature" do
    transaction = Transaction.create!(
      public_key: "receiver-public-key",
      digital_signature: "sender-digital-signature",
      receiver_output_value: "2",
      input_transaction_ids: [transactions(:first_previous).id]
    )

    transaction.reload

    assert_equal "receiver-public-key", transaction.public_key
    assert_equal "sender-digital-signature", transaction.digital_signature
  end

  test "stores blocks candidate blocks nodes and transactions in the prototype" do
    domain_tables = ApplicationRecord.connection.tables - %w[schema_migrations ar_internal_metadata]

    assert_equal ["blocks", "candidate_blocks", "nodes", "transactions"], domain_tables.sort
    assert_includes Transaction.column_names, "block_id"
  end

  test "saved public keys and signatures cannot change" do
    transaction = Transaction.create!(
      public_key: "original-public-key",
      digital_signature: "original-signature",
      receiver_output_value: "2",
      input_transaction_ids: [transactions(:first_previous).id]
    )

    [{ public_key: "updated-public-key" }, { digital_signature: "updated-signature" }].each do |change|
      assert_not transaction.update(change)
      assert_equal ["Transaction content cannot change after creation"], transaction.errors.full_messages
      transaction.reload
      assert_equal "original-public-key", transaction.public_key
      assert_equal "original-signature", transaction.digital_signature
    end
  end

  test "stores the receiver output value as a decimal amount" do
    previous = transactions(:first_previous)
    ["12.34567890", "0", "0.00000001"].each do |value|
      transaction = Transaction.create!(public_key: "receiver-public-key", receiver_output_value: value, input_transaction_ids: [previous.id])

      assert_equal BigDecimal(value), transaction.reload.receiver_output_value
    end
  end

  test "requires a numeric receiver output value" do
    [nil, "", "not-a-number"].each do |value|
      transaction = Transaction.new(public_key: "receiver-public-key", receiver_output_value: value, input_transaction_ids: [transactions(:first_previous).id])

      assert_not transaction.valid?
      assert_equal({ receiver_output_value: ["is not a number"] }, transaction.errors.to_hash)
    end
  end

  test "requires a public key when creating a transaction" do
    [nil, "", " \t\n"].each do |key|
      transaction = Transaction.new(public_key: key, receiver_output_value: "2", input_transaction_ids: [transactions(:first_previous).id])

      assert_no_difference "Transaction.count" do
        assert_not transaction.save
      end

      assert_equal ["Public key can't be blank"], transaction.errors.full_messages
    end
  end

  test "a saved public key cannot be cleared" do
    transaction = Transaction.create!(public_key: "receiver-public-key", receiver_output_value: "2", input_transaction_ids: [transactions(:first_previous).id])

    assert_not transaction.update(public_key: nil)
    assert_equal ["Transaction content cannot change after creation"], transaction.errors.full_messages
    assert_equal "receiver-public-key", transaction.reload.public_key
  end
end
