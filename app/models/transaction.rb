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
  after_create :update_unspent_outputs

  private

  def update_unspent_outputs
    inputs.each do |input|
      UnspentOutput.where(transaction_id: input.fetch("previous_transaction_id"), output_index: input.fetch("output_index")).delete_all
    end
    outputs.each_index { |index| UnspentOutput.create!(transaction_id: id, output_index: index) }
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
      normalized["value"] = OUTPUT_VALUE_TYPE.serialize(value) if value&.finite?
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
      unless decimal_value(output.fetch("value"))&.finite?
        errors.add(:outputs, "item #{index} value must be a finite number")
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
