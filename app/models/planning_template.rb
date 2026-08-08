class PlanningTemplate < ApplicationRecord
  include CurrencyQualified

  enum :kind, {
    paycheck: "paycheck",
    subscription: "subscription",
    bill: "bill",
    payment_plan: "payment_plan",
    credit_card_payment: "credit_card_payment"
  }, prefix: true
  enum :flow_kind, { income: "income", outflow: "outflow", transfer: "transfer" }, prefix: true
  enum :budget_group, {
    fixed: "fixed",
    variable: "variable",
    debt: "debt",
    savings: "savings",
    other: "other"
  }, prefix: true

  belongs_to :budget_workspace
  belongs_to :category, optional: true
  belongs_to :source_account, class_name: "Account", optional: true
  belongs_to :destination_account, class_name: "Account", optional: true
  has_one :recurrence_rule, dependent: :restrict_with_error
  has_one :payment_plan_term, dependent: :restrict_with_error
  has_one :credit_card_payment_policy, dependent: :restrict_with_error
  has_many :recurring_occurrences, dependent: :restrict_with_error

  validates :name, presence: true
  validates :default_amount, numericality: { greater_than_or_equal_to: 0 }
  validate :active_window_is_coherent
  validate :accounts_are_distinct

  scope :active, -> { where(archived_at: nil) }

  private

  def active_window_is_coherent
    return if active_from.blank? || active_until.blank? || active_until >= active_from

    errors.add(:active_until, "must be on or after active from")
  end

  def accounts_are_distinct
    return if source_account_id.blank? || destination_account_id.blank?
    return unless source_account_id == destination_account_id

    errors.add(:destination_account, "must differ from source account")
  end
end
