class BudgetItem < ApplicationRecord
  include CurrencyQualified

  enum :flow_kind, { income: "income", outflow: "outflow", transfer: "transfer" }, prefix: true
  enum :budget_group, {
    fixed: "fixed",
    variable: "variable",
    debt: "debt",
    savings: "savings",
    other: "other"
  }, prefix: true
  enum :state, {
    open: "open",
    skipped: "skipped",
    cancelled: "cancelled",
    voided: "voided"
  }, prefix: true
  enum :origin_kind, {
    manual: "manual",
    recurring: "recurring",
    clone: "clone",
    budget_import: "budget_import",
    migration: "migration"
  }, prefix: true

  belongs_to :budget_workspace
  belongs_to :budget_period
  belongs_to :category, optional: true
  belongs_to :recurring_occurrence, optional: true
  belongs_to :intended_source_account, class_name: "Account", optional: true
  belongs_to :intended_destination_account, class_name: "Account", optional: true
  has_many :budget_allocations, dependent: :restrict_with_error
  has_many :financial_transactions, through: :budget_allocations
  has_many :month_close_item_snapshots, dependent: :restrict_with_error

  validates :planned_amount, numericality: { greater_than_or_equal_to: 0 }
  validate :accounts_are_distinct
  validate :void_state_is_coherent

  def allocated_amount
    budget_allocations.sum(:amount)
  end

  def remaining_amount
    [ planned_amount - allocated_amount, 0 ].max
  end

  private

  def accounts_are_distinct
    return if intended_source_account_id.blank? || intended_destination_account_id.blank?
    return unless intended_source_account_id == intended_destination_account_id

    errors.add(:intended_destination_account, "must differ from intended source account")
  end

  def void_state_is_coherent
    coherent = state_voided? ? voided_at.present? && void_reason.present? : voided_at.blank? && void_reason.blank?
    errors.add(:voided_at, "must match the void state") unless coherent
  end
end
