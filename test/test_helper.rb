ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Test-only starting state until coinbase exists. These synthetic snapshots
    # bypass creation callbacks; no application path may use them to issue coins.
    def prepare_unspent_transaction(values: ["5"], id: SecureRandom.hex(32))
      outputs = values.map { |value| { value: BigDecimal(value).to_s("F"), script_pub_key: { operation: "OP_CHECKSIG", public_key: "prepared-owner" } } }
      Transaction.insert_all!([{ id: id, inputs: [{ previous_transaction_id: "f" * 64, output_index: 0, script_sig: "prepared-state" }], outputs: outputs }])
      values.each_index { |index| UnspentOutput.create!(transaction_id: id, output_index: index) }
      Transaction.find(id)
    end

    def transaction_attributes(previous_id: "a" * 64, output_index: 0, signature: "sender-signature", value: "2.125", public_key: "receiver-public-key")
      {
        inputs: [{ previous_transaction_id: previous_id, output_index: output_index, script_sig: signature }],
        outputs: [{ value: value, script_pub_key: { operation: "OP_CHECKSIG", public_key: public_key } }]
      }
    end
  end
end
