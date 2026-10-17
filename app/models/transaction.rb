class Transaction < ApplicationRecord
  include HashIdentity

  INPUT_FIELDS = %w[previous_transaction_id output_index script_sig].freeze
  OUTPUT_FIELDS = %w[value script_pub_key].freeze
  SCRIPT_FIELDS = %w[operation public_key].freeze
  SCRIPT_OPERATION = "OP_CHECKSIG"
  OUTPUT_POSITION_RANGE = (0..4_294_967_295)
  OUTPUT_VALUE_TYPE = ExactDecimal.new(precision: 20, scale: 8)

  belongs_to :block, optional: true
  has_many :unspent_outputs, inverse_of: :source_transaction

  before_validation :normalize_content, on: :create
  validate :input_structure, on: :create
  validate :output_structure, on: :create
  validate :spending_rules, on: :create
  after_create :update_unspent_outputs

  # A caller may rescue a failed save inside a larger transaction. Keep each
  # new payment's history and output changes inside their own rollback boundary.
  def save(**options, &block)
    return super unless new_record?

    self.class.transaction(requires_new: true) do
      saved = super
      raise ActiveRecord::Rollback unless saved
      saved
    end || false
  end

  def save!(**options, &block)
    return super unless new_record?

    self.class.transaction(requires_new: true) { super }
  end

  private

  def update_unspent_outputs
    inputs.each_with_index do |input, index|
      removed = UnspentOutput.where(transaction_id: input.fetch("previous_transaction_id"), output_index: input.fetch("output_index")).delete_all
      unless removed == 1
        add_unavailable_input_error(index)
        raise ActiveRecord::RecordInvalid, self
      end
    end
    outputs.each_index { |index| UnspentOutput.create!(transaction_id: id, output_index: index) }
  end

  def spending_rules
    return if errors.any?

    references = Set.new
    inputs.each_with_index do |input, index|
      reference = [input.fetch("previous_transaction_id"), input.fetch("output_index")]
      errors.add(:inputs, "item #{index} repeats a previous output") unless references.add?(reference)
    end
    return if errors.any?

    input_value = BigDecimal("0")
    inputs.each_with_index do |input, index|
      available = UnspentOutput.find_by(transaction_id: input.fetch("previous_transaction_id"), output_index: input.fetch("output_index"))
      if available
        input_value += BigDecimal(available.output.fetch("value"))
      else
        add_unavailable_input_error(index)
      end
    end
    return if errors.any?

    output_value = outputs.sum { |output| BigDecimal(output.fetch("value")) }
    errors.add(:outputs, "total value must not exceed total input value") if output_value > input_value
  end

  def add_unavailable_input_error(index)
    errors.add(:inputs, "item #{index} references a missing or spent output")
  end

  def identity_attributes
    %w[inputs outputs]
  end

  def calculate_id
    input_values = inputs.map { |input| INPUT_FIELDS.map { |field| input.fetch(field) } }
    output_values = outputs.map do |output|
      script = output.fetch("script_pub_key")
      [output.fetch("value"), script.fetch("operation"), script.fetch("public_key")]
    end
    ContentHash.calculate("transaction", input_values, output_values)
  end

  def normalize_content
    self.inputs = inputs.map { |input| input.is_a?(Hash) ? input.deep_stringify_keys : input } if inputs.is_a?(Array)
    return unless outputs.is_a?(Array)

    self.outputs = outputs.map do |output|
      next output unless output.is_a?(Hash)
      normalized = output.deep_stringify_keys
      value = decimal_value(normalized["value"])
      normalized["value"] = OUTPUT_VALUE_TYPE.serialize(value) if value&.finite? && !value.negative?
      normalized
    end
  end

  def decimal_value(value)
    return unless value.is_a?(String) || value.is_a?(Numeric)
    BigDecimal(value.to_s, exception: false)
  end

  def validate_list(name, fields)
    entries = public_send(name)
    unless entries.is_a?(Array) && !entries.empty?
      errors.add(name, "must be a non-empty array")
      return
    end
    entries.each_with_index do |entry, index|
      unless entry.is_a?(Hash) && entry.keys.sort == fields.sort
        errors.add(name, "item #{index} must contain exactly #{fields.join(', ')}")
        next
      end
      yield entry, index
    end
  end

  def input_structure
    validate_list(:inputs, INPUT_FIELDS) do |input, index|
      hash = input.fetch("previous_transaction_id")
      unless hash.is_a?(String) && ContentHash::FORMAT.match?(hash)
        errors.add(:inputs, "item #{index} previous_transaction_id must be a lowercase 64-character hash")
      end
      position = input.fetch("output_index")
      unless position.is_a?(Integer) && OUTPUT_POSITION_RANGE.cover?(position)
        errors.add(:inputs, "item #{index} output_index must be an integer from 0 through 4294967295")
      end
      unless input.fetch("script_sig").is_a?(String)
        errors.add(:inputs, "item #{index} script_sig must be a string")
      end
    end
  end

  def output_structure
    validate_list(:outputs, OUTPUT_FIELDS) do |output, index|
      value = decimal_value(output.fetch("value"))
      if !value&.finite?
        errors.add(:outputs, "item #{index} value must be a finite number")
      elsif value.negative?
        errors.add(:outputs, "item #{index} value must not be negative")
      end
      script = output.fetch("script_pub_key")
      unless script.is_a?(Hash) && script.keys.sort == SCRIPT_FIELDS.sort
        errors.add(:outputs, "item #{index} script_pub_key must contain exactly operation, public_key")
        next
      end
      unless script.fetch("operation") == SCRIPT_OPERATION
        errors.add(:outputs, "item #{index} script_pub_key operation must be OP_CHECKSIG")
      end
      key = script.fetch("public_key")
      unless key.is_a?(String) && key.present?
        errors.add(:outputs, "item #{index} script_pub_key public_key must be a nonblank string")
      end
    end
  end
end
