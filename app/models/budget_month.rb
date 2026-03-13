class BudgetMonth < ApplicationRecord
  belongs_to :user
  has_many :expense_entries, dependent: :destroy

  validates :label, presence: true
  validates :month_on, presence: true, uniqueness: { scope: :user_id }

  scope :recent_first, -> { order(month_on: :desc) }

  def income_total
    base_income = actual_income.presence || planned_income.presence || 0
    base_income + expense_entries.income.sum(&:effective_amount)
  end

  def outflow_total
    expense_entries.where.not(section: ExpenseEntry.sections[:income]).sum(&:effective_amount)
  end

  def calculated_leftover
    income_total - outflow_total
  end

  def section_total(section_key)
    expense_entries.where(section: ExpenseEntry.sections[section_key]).sum(&:effective_amount)
  end

  def complete_for_generation?
    month_on.present? && month_on < Date.current.beginning_of_month && expense_entries.exists? && expense_entries.where(status: ExpenseEntry.statuses[:planned]).none?
  end
end
