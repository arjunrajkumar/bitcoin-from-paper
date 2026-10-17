require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  test "stores blocks candidate blocks nodes and transactions in the prototype" do
    domain_tables = ApplicationRecord.connection.tables - %w[schema_migrations ar_internal_metadata]
    assert_equal ["blocks", "candidate_blocks", "nodes", "transactions", "unspent_outputs"], domain_tables.sort
    assert_includes Transaction.column_names, "block_id"
  end

  test "stores output amounts as exact decimal text" do
    ["12.34567890", "0", "0.00000001"].each do |value|
      transaction = Transaction.create!(transaction_attributes(value: value))
      assert_equal BigDecimal(value), BigDecimal(transaction.reload.outputs.first.fetch("value"))
    end
  end

  test "requires finite numeric output values" do
    [nil, "", "not-a-number", "NaN", "Infinity", "-Infinity", true, {}, []].each do |value|
      assert_invalid(transaction_attributes(value: value), "Outputs item 0 value must be a finite number")
    end
  end

  test "requires a public key on each output" do
    [nil, "", " \t\n", 17, [], {}].each do |key|
      assert_invalid(transaction_attributes(public_key: key), "Outputs item 0 script_pub_key public_key must be a nonblank string")
    end
  end

  test "requires nonempty input and output arrays" do
    [:inputs, :outputs].each do |field|
      [nil, [], {}, "invalid", 1, true].each do |value|
        assert_invalid(transaction_attributes.merge(field => value), "#{field.to_s.capitalize} must be a non-empty array")
      end
    end
  end

  test "rejects missing and unknown fields in every list item" do
    { inputs: %i[previous_transaction_id output_index script_sig], outputs: %i[value script_pub_key] }.each do |name, fields|
      valid = transaction_attributes.fetch(name).first
      entries = [nil, 1, "invalid", [], {}] + fields.map { |field| valid.except(field) } + [valid.merge(extra: "not allowed")]
      entries.each do |entry|
        assert_invalid(transaction_attributes.merge(name => [entry]), "#{name.to_s.capitalize} item 0 must contain exactly #{fields.join(', ')}")
      end
    end
  end

  test "requires the exact supported spending condition shape" do
    [nil, "OP_CHECKSIG", [], {}, { operation: "OP_CHECKSIG" }, { public_key: "key" }, { operation: "OP_CHECKSIG", public_key: "key", block_height: 100 }].each do |script|
      attributes = transaction_attributes
      attributes[:outputs].first[:script_pub_key] = script
      assert_invalid(attributes, "Outputs item 0 script_pub_key must contain exactly operation, public_key")
    end
  end

  test "requires a valid previous hash and integer output position" do
    [nil, "", "a", "A" * 64, "g" * 64, 1, []].each do |hash|
      assert_invalid(transaction_attributes(previous_id: hash), "Inputs item 0 previous_transaction_id must be a lowercase 64-character hash")
    end
    [nil, -1, 4_294_967_296, 1.5, "0", false].each do |position|
      assert_invalid(transaction_attributes(output_index: position), "Inputs item 0 output_index must be an integer from 0 through 4294967295")
    end
    [0, 1, 4_294_967_295].each do |position|
      transaction = Transaction.create!(transaction_attributes(output_index: position))
      assert_equal position, transaction.reload.inputs.first.fetch("output_index")
    end
  end

  test "input proofs are strings and may be empty before signature verification exists" do
    [nil, 1, false, [], {}].each do |proof|
      assert_invalid(transaction_attributes(signature: proof), "Inputs item 0 script_sig must be a string")
    end
    ["", "not-a-real-signature"].each do |proof|
      transaction = Transaction.create!(transaction_attributes(signature: proof))
      assert_equal proof, transaction.reload.inputs.first.fetch("script_sig")
    end
  end

  test "nested edits to a saved public key or signature fail" do
    transaction = Transaction.create!(transaction_attributes)
    original = transaction.reload.attributes.deep_dup
    transaction.outputs.first.fetch("script_pub_key")["public_key"] = nil
    assert_not transaction.save
    assert_equal ["Transaction content cannot change after creation"], transaction.errors.full_messages
    assert_equal original, transaction.reload.attributes
    transaction.inputs.first["script_sig"] = "replacement"
    assert_not transaction.save
    assert_equal ["Transaction content cannot change after creation"], transaction.errors.full_messages
    assert_equal original, transaction.reload.attributes
  end

  private

  def assert_invalid(attributes, message)
    transaction = Transaction.new(attributes)
    assert_no_difference "Transaction.count" do
      assert_not transaction.save
    end
    assert_equal [message], transaction.errors.full_messages
  end
end
