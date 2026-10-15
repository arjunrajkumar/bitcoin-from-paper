class ExactDecimal < ActiveRecord::Type::Decimal
  def serialize(value)
    decimal = super
    return if decimal.nil?

    # Bind text so SQLite does not convert an exact amount through a Float.
    decimal.zero? ? "0.0" : decimal.to_s("F")
  end
end
