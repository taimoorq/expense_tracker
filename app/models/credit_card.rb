class CreditCard < ApplicationRecord
  include TemplateAccountLinkable

  belongs_to :user
  belongs_to :payment_account, class_name: "Account", optional: true
  template_account_association :linked_account
  alias_attribute :linked_account_id, :payment_account_id

  validates :name, presence: true
  validates :minimum_payment, presence: true
  validates :priority, presence: true
  validates :due_day, presence: true, inclusion: { in: 1..31 }

  scope :active_only, -> { where(active: true).order(:priority, :name) }

  def matches_entry?(entry)
    return false if entry.blank?
    return false unless comparable_text(entry.payee) == comparable_text(name)

    entry.source_file == "credit_card_estimate" || (entry.debt? && comparable_text(entry.category).include?("credit card"))
  end

  # Compatibility layer: keep legacy payment_account naming while exposing
  # the shared linked_account interface used by other templates.
  def linked_account
    payment_account
  end

  def linked_account=(account)
    self.payment_account = account
  end

  private

  def comparable_text(value)
    value.to_s.strip.downcase
  end
end
