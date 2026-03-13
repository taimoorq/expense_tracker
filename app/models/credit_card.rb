class CreditCard < ApplicationRecord
  validates :name, presence: true
  validates :minimum_payment, presence: true
  validates :priority, presence: true

  scope :active_only, -> { where(active: true).order(:priority, :name) }
end
