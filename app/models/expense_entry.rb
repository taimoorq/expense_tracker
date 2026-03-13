class ExpenseEntry < ApplicationRecord
  belongs_to :user
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
  validate :user_matches_budget_month

  before_validation :assign_user_from_budget_month

  scope :chronological, -> { order(:occurred_on, :created_at) }

  def effective_amount
    actual_amount.presence || planned_amount.presence || 0
  end

  def cashflow_amount
    income? ? effective_amount : -effective_amount
  end

  private

  def assign_user_from_budget_month
    self.user ||= budget_month&.user
  end

  def user_matches_budget_month
    return if user.blank? || budget_month.blank?
    return if user_id == budget_month.user_id

    errors.add(:user, "must match the budget month owner")
  end
end
