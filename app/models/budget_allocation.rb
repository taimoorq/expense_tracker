class BudgetAllocation < ApplicationRecord
  include CurrencyQualified

  enum :match_kind, {
    manual: "manual",
    suggested: "suggested",
    exact_import: "exact_import",
    migration: "migration"
  }, prefix: true

  belongs_to :budget_workspace
  belongs_to :budget_item
  belongs_to :financial_transaction
  belongs_to :matched_by_membership, class_name: "WorkspaceMembership", optional: true

  validates :amount, numericality: { greater_than: 0 }
  validates :match_confidence, numericality: { in: 0..1 }, allow_nil: true
  validates :financial_transaction_id, uniqueness: { scope: :budget_item_id }
  validates :matched_at, presence: true
  validate :currency_matches_both_sides

  private

  def currency_matches_both_sides
    if budget_item.present? && currency_code != budget_item.currency_code
      errors.add(:currency_code, "must match the budget item currency")
    end
    if financial_transaction.present? && currency_code != financial_transaction.currency_code
      errors.add(:currency_code, "must match the transaction currency")
    end
  end
end
