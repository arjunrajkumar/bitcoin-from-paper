class Transaction < ApplicationRecord
  include HashIdentity

  # SQLite NUMERIC storage can round large amounts through a floating-point value.
  attribute :receiver_output_value, ExactDecimal.new(precision: 20, scale: 8)

  belongs_to :block, optional: true

  validates :input_transaction_ids, presence: true, on: :create
  validates :public_key, presence: true, on: :create
  validates :receiver_output_value, numericality: true, on: :create
  validate :input_hash_format, on: :create
  validate :finite_output_value, on: :create

  private

  def identity_attributes
    %w[input_transaction_ids input_count receiver_output_value public_key digital_signature]
  end

  def calculate_id
    value = self.class.type_for_attribute("receiver_output_value").serialize(receiver_output_value)
    ContentHash.calculate("transaction", input_transaction_ids, input_count, value, public_key, digital_signature)
  end

  def input_hash_format
    return if input_transaction_ids.blank?
    unless input_transaction_ids.is_a?(Array) && input_transaction_ids.all? { |value| value.is_a?(String) && ContentHash::FORMAT.match?(value) }
      errors.add(:input_transaction_ids, "must be an array of lowercase 64-character hashes")
    end
  end

  def finite_output_value
    if receiver_output_value && !receiver_output_value.finite?
      errors.add(:receiver_output_value, "must be finite")
    end
  end
end
