require "securerandom"

module SeedIdentity
  extend ActiveSupport::Concern
  include HashIdentity

  included do
    before_validation :assign_identity_seed, on: :create
    validates :identity_seed, format: { with: ContentHash::FORMAT, message: "must be 64 lowercase hexadecimal characters" }, on: :create
  end

  private

  def assign_identity_seed
    self.identity_seed ||= SecureRandom.hex(32)
  end

  def identity_attributes
    ["identity_seed"]
  end
end
