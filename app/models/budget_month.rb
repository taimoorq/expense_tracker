class BudgetMonth < ApplicationRecord
  belongs_to :user
  has_many :expense_entries, dependent: :destroy

  validates :label, presence: true
  validates :month_on, presence: true, uniqueness: { scope: :user_id }

  scope :recent_first, -> { order(month_on: :desc) }

  def income_total
    itemized_income =
      if expense_entries_association_loaded?
        loaded_expense_entries.select(&:income?).sum(&:effective_amount)
      else
        expense_entries.income.sum(&:effective_amount)
      end

    return itemized_income if itemized_income.positive?

    0
  end

  def outflow_total
    if expense_entries_association_loaded?
      loaded_expense_entries.reject(&:income?).sum(&:effective_amount)
    else
      expense_entries.where.not(section: ExpenseEntry.sections[:income]).sum(&:effective_amount)
    end
  end

  def calculated_leftover
    income_total - outflow_total
  end

  def section_total(section_key)
    if expense_entries_association_loaded?
      loaded_expense_entries.select { |entry| entry.section == section_key.to_s }.sum(&:effective_amount)
    else
      expense_entries.where(section: ExpenseEntry.sections[section_key]).sum(&:effective_amount)
    end
  end

  def complete_for_generation?
    month_on.present? && month_on < Date.current.beginning_of_month && expense_entries.exists? && expense_entries.where(status: ExpenseEntry.statuses[:planned]).none?
  end

  private

  def expense_entries_association_loaded?
    association(:expense_entries).loaded?
  end

  def loaded_expense_entries
    association(:expense_entries).target
  end
end
