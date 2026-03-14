class CreditCard < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :minimum_payment, presence: true
  validates :priority, presence: true

  scope :active_only, -> { where(active: true).order(:priority, :name) }

  def matches_entry?(entry)
    return false if entry.blank?
    return false unless comparable_text(entry.payee) == comparable_text(name)

    entry.source_file == "credit_card_estimate" || (entry.debt? && comparable_text(entry.category).include?("credit card"))
  end

  private

  def comparable_text(value)
    value.to_s.strip.downcase
  end
end
