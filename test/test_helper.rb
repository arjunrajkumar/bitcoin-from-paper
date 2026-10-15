ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    def transaction_attributes(previous_id: "a" * 64, output_index: 0, signature: "sender-signature", value: "2.125", public_key: "receiver-public-key")
      {
        inputs: [{ previous_transaction_id: previous_id, output_index: output_index, script_sig: signature }],
        outputs: [{ value: value, script_pub_key: { operation: "OP_CHECKSIG", public_key: public_key } }]
      }
    end
  end
end
