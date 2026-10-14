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

  test "stores the public key and digital signature without a block" do
    transaction = Transaction.create!(
      public_key: "receiver-public-key",
      digital_signature: "sender-digital-signature",
      receiver_output_value: "2",
      input_transaction_ids: [transactions(:first_previous).id]
    )

    transaction.reload

    assert_equal "receiver-public-key", transaction.public_key
    assert_equal "sender-digital-signature", transaction.digital_signature
    assert_nil transaction.block
  end

  test "stores the public key and digital signature with a block" do
    block = Block.create!
    transaction = block.transactions.create!(
      public_key: "another-receiver-public-key",
      digital_signature: "another-sender-digital-signature",
      receiver_output_value: "2",
      input_transaction_ids: [transactions(:first_previous).id]
    )

    transaction.reload

    assert_equal "another-receiver-public-key", transaction.public_key
    assert_equal "another-sender-digital-signature", transaction.digital_signature
    assert_equal block, transaction.block
  end

  test "updates the public key and signature independently" do
    transaction = Transaction.create!(
      public_key: "original-public-key",
      digital_signature: "original-signature",
      receiver_output_value: "2",
      input_transaction_ids: [transactions(:first_previous).id]
    )

    transaction.update!(public_key: "updated-public-key")
    transaction.reload

    assert_equal "updated-public-key", transaction.public_key
    assert_equal "original-signature", transaction.digital_signature

    transaction.update!(digital_signature: "updated-signature")
    transaction.reload

    assert_equal "updated-public-key", transaction.public_key
    assert_equal "updated-signature", transaction.digital_signature
  end

  test "stores the receiver output value as a decimal amount" do
    previous = transactions(:first_previous)
    ["12.34567890", "0", "0.00000001"].each do |value|
      previous.update!(receiver_output_value: value)
      transaction = Transaction.create!(public_key: "receiver-public-key", receiver_output_value: value, input_transaction_ids: [previous.id])

      assert_equal BigDecimal(value), transaction.reload.receiver_output_value
    end
  end

  test "does not create a transaction when the receiver value exceeds the input value" do
    previous = transactions(:first_previous)
    previous.update!(receiver_output_value: "2")
    transaction = Transaction.new(public_key: "receiver-public-key", receiver_output_value: "5", input_transaction_ids: [previous.id])

    assert_no_difference "Transaction.count" do
      assert_not transaction.save
    end

    assert_equal ["Receiver output value must be less than or equal to total input value"], transaction.errors.full_messages
  end

  test "compares exact decimal values at and across the equality boundary" do
    previous = transactions(:first_previous)
    (0..3).each do |input_units|
      previous.update!(receiver_output_value: BigDecimal(input_units) / 100_000_000)
      (0..3).each do |output_units|
        transaction = Transaction.new(
          public_key: "receiver-public-key",
          receiver_output_value: BigDecimal(output_units) / 100_000_000,
          input_transaction_ids: [previous.id]
        )
        expected_to_save = input_units >= output_units

        assert_equal expected_to_save, transaction.save
        expected_errors = expected_to_save ? [] : ["Receiver output value must be less than or equal to total input value"]
        assert_equal expected_errors, transaction.errors.full_messages
      end
    end
  end

  test "requires a numeric receiver output value" do
    [nil, "", "not-a-number"].each do |value|
      transaction = Transaction.new(public_key: "receiver-public-key", receiver_output_value: value, input_transaction_ids: [transactions(:first_previous).id])

      assert_not transaction.valid?
      assert_equal({ receiver_output_value: ["is not a number"] }, transaction.errors.to_hash)
    end
  end

  test "rejects non-finite receiver output values" do
    [BigDecimal("NaN"), BigDecimal("Infinity"), BigDecimal("-Infinity")].each do |value|
      transaction = Transaction.new(public_key: "receiver-public-key", receiver_output_value: value, input_transaction_ids: [transactions(:first_previous).id])

      assert_not transaction.valid?
      assert_equal({ receiver_output_value: ["must be finite"] }, transaction.errors.to_hash)
    end
  end

  test "runs the value checks on creation only" do
    transaction = Transaction.create!(public_key: "receiver-public-key", receiver_output_value: "2", input_transaction_ids: [transactions(:first_previous).id])

    assert transaction.update(receiver_output_value: "6")
    assert_equal BigDecimal("6"), transaction.reload.receiver_output_value
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

  test "checks public key presence on creation only" do
    transaction = Transaction.create!(public_key: "receiver-public-key", receiver_output_value: "2", input_transaction_ids: [transactions(:first_previous).id])

    assert transaction.update(public_key: nil)
    assert_nil transaction.reload.public_key
  end
end
