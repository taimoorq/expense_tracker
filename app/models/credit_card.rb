class CreditCard < ApplicationRecord
  include PlanningTemplateMetadata
  include TemplateAccountLinkable

  ESTIMATE_ENTRY_KEY_VERSION = "credit-card-estimate:v1".freeze
  ESTIMATE_NOTES = "Estimated from leftover cash".freeze

  belongs_to :user
  belongs_to :linked_account, class_name: "Account", optional: true
  belongs_to :payment_account, class_name: "Account", optional: true
  template_account_association :linked_account
  entry_account_association :payment_account
  planning_template_metadata(
    type_key: :credit_card,
    source_file: "credit_card_estimate",
    param_key: :credit_card,
    recurring_source: false,
    wizard_sections: [],
    permitted_attributes: [ :name, :minimum_payment, :due_day, :priority, :linked_account_id, :payment_account_id, :account, :active, :notes ]
  )

  validates :name, presence: true
  validates :minimum_payment, presence: true
  validates :minimum_payment, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :priority, presence: true
  validates :due_day, presence: true, inclusion: { in: 1..31 }
  validate :payment_account_belongs_to_user

  scope :active_only, -> { where(active: true).order(:priority, :name) }

  def matches_entry?(entry, month_on: nil)
    matches_entry_for_month?(entry, month_on: month_on)
  end

  def matches_entry_for_month?(entry, month_on: nil)
    return false if entry.blank?
    return false unless comparable_text(entry.payee) == comparable_text(name)
    return false unless matching_account?(entry)

    entry.source_file == "credit_card_estimate" || (entry.debt? && comparable_text(entry.category).include?("credit card"))
  end

  def estimated_entry_key(month_on:)
    return nil if id.blank? || month_on.blank?

    [
      ESTIMATE_ENTRY_KEY_VERSION,
      self.class.name,
      id,
      month_on.to_date.beginning_of_month.iso8601
    ].join(":")
  end

  def build_estimated_entry_attributes(month_on:, amount:)
    month_start = month_on.to_date.beginning_of_month

    {
      generated_entry_key: estimated_entry_key(month_on: month_start),
      occurred_on: month_start.change(day: [ due_day.to_i, month_start.end_of_month.day ].min),
      section: :debt,
      category: "Credit Card",
      payee: name,
      planned_amount: amount.round(2),
      actual_amount: nil,
      account: account_name,
      status: :planned,
      need_or_want: "Need",
      notes: ESTIMATE_NOTES,
      source_file: CreditCard.template_source_file,
      source_template: self
    }
  end

  private

  def comparable_text(value)
    value.to_s.strip.downcase
  end

  def matching_account?(entry)
    expected_account = account_name
    return true if expected_account.blank?

    comparable_text(entry.account_name) == comparable_text(expected_account)
  end

  def payment_account_belongs_to_user
    return if payment_account.blank? || payment_account.user_id == user_id

    errors.add(:payment_account, "must belong to the same user")
  end
end
