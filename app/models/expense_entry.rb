class ExpenseEntry < ApplicationRecord
  belongs_to :budget_month

  enum :section, {
    income: 0,
    fixed: 1,
    variable: 2,
    debt: 3,
    manual: 4,
    auto: 5,
    other: 6
  }

  enum :status, {
    planned: 0,
    paid: 1,
    skipped: 2
  }

  validates :section, presence: true
  validates :status, presence: true

  scope :chronological, -> { order(:occurred_on, :created_at) }

  def effective_amount
    actual_amount.presence || planned_amount.presence || 0
  end

  def cashflow_amount
    income? ? effective_amount : -effective_amount
  end
end
