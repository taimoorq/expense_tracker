class CreditCard < ApplicationRecord
  include TemplateAccountLinkable

  belongs_to :user
  belongs_to :linked_account, class_name: "Account", optional: true
  belongs_to :payment_account, class_name: "Account", optional: true
  template_account_association :linked_account

  validates :name, presence: true
  validates :minimum_payment, presence: true
  validates :priority, presence: true
  validates :due_day, presence: true, inclusion: { in: 1..31 }
  validate :payment_account_belongs_to_user

  scope :active_only, -> { where(active: true).order(:priority, :name) }

  def matches_entry?(entry)
    return false if entry.blank?
    return false unless comparable_text(entry.payee) == comparable_text(name)

    entry.source_file == "credit_card_estimate" || (entry.debt? && comparable_text(entry.category).include?("credit card"))
  end

  def account_name
    payment_account&.name.presence || account
  end

  private

  def comparable_text(value)
    value.to_s.strip.downcase
  end

  def payment_account_belongs_to_user
    return if payment_account.blank? || payment_account.user_id == user_id

    errors.add(:payment_account, "must belong to the same user")
  end
end
