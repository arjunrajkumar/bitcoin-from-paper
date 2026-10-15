module HashIdentity
  extend ActiveSupport::Concern

  included do
    before_create :assign_hash_identity
    before_update :prevent_identity_changes
  end

  private

  def assign_hash_identity
    expected = calculate_id
    if id && id != expected
      errors.add(:id, "must match the calculated hash")
      throw :abort
    end
    self.id = expected
  end

  def prevent_identity_changes
    if (["id"] + identity_attributes).any? { |name| will_save_change_to_attribute?(name) }
      errors.add(:base, "#{self.class.name} content cannot change after creation")
      throw :abort
    end
  end
end
