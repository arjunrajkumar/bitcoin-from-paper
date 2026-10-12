class Transaction < ApplicationRecord
  belongs_to :block, optional: true
end
