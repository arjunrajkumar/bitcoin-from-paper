class Transaction < ApplicationRecord
  belongs_to :block, optional: true

  validates :input_transaction_ids, presence: true, on: :create
  validates :public_key, presence: true, on: :create
  validates :receiver_output_value, numericality: true, on: :create

  validate :inputs_belong_to_same_sender, on: :create
  validate :input_value_covers_receiver_output_value, on: :create
  validate :digital_signature_matches_input_public_keys, on: :create

  def total_input_value
    values = Transaction.find(input_transaction_ids).map(&:receiver_output_value)
    return if values.any?(&:nil?)

    values.sum(BigDecimal("0"))
  end

  private

  def input_value_covers_receiver_output_value
    if receiver_output_value && !receiver_output_value.finite?
      errors.add(:receiver_output_value, "must be finite")
    end

    return if errors[:input_transaction_ids].any? || errors[:receiver_output_value].any?

    input_value = total_input_value
    if input_value.nil?
      errors.add(:total_input_value, "is not a number")
    elsif !input_value.finite?
      errors.add(:total_input_value, "must be finite")
    elsif input_value < receiver_output_value
      errors.add(:receiver_output_value, "must be less than or equal to total input value")
    end
  end

  # Ownership and signature checks are deferred to a later learning step.
  def inputs_belong_to_same_sender
    true
  end

  def digital_signature_matches_input_public_keys
    true
  end
end
