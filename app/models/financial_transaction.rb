class FinancialTransaction < ApplicationRecord
  include CurrencyQualified

  enum :flow_kind, {
    income: "income",
    outflow: "outflow",
    transfer: "transfer",
    adjustment: "adjustment"
  }, prefix: true
  enum :state, {
    pending: "pending",
    posted: "posted",
    voided: "voided",
    reversed: "reversed"
  }, prefix: true
  enum :origin_kind, {
    manual: "manual",
    institution_import: "institution_import",
    migration: "migration",
    system_adjustment: "system_adjustment"
  }, prefix: true

  belongs_to :budget_workspace
  belongs_to :category, optional: true
  belongs_to :reversal_transaction, class_name: "FinancialTransaction", optional: true
  belongs_to :import_row, optional: true
  has_many :account_postings, dependent: :restrict_with_error
  has_many :budget_allocations, dependent: :restrict_with_error
  has_many :budget_items, through: :budget_allocations
  has_many :month_close_transaction_snapshots, dependent: :restrict_with_error

  validates :effective_on, :description, presence: true
  validates :gross_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :idempotency_key, uniqueness: { scope: :budget_workspace_id }, allow_nil: true
  validate :void_state_is_coherent

  def allocated_amount
    budget_allocations.sum(:amount)
  end

  def available_to_allocate
    [ gross_amount - allocated_amount, 0 ].max
  end

  private

  def void_state_is_coherent
    coherent = state_voided? ? voided_at.present? && void_reason.present? : voided_at.blank? && void_reason.blank?
    errors.add(:voided_at, "must match the void state") unless coherent
  end
end
