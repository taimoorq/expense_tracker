class BudgetPeriod < ApplicationRecord
  include CurrencyQualified

  enum :state, {
    open: "open",
    closing: "closing",
    closed: "closed",
    reopened: "reopened"
  }, prefix: true

  belongs_to :budget_workspace
  has_many :budget_items, dependent: :restrict_with_error
  has_many :recurring_occurrences, dependent: :restrict_with_error
  has_many :month_closes, dependent: :restrict_with_error

  validates :starts_on, presence: true, uniqueness: { scope: :budget_workspace_id }
  validate :starts_on_first_day

  def label
    starts_on&.strftime("%B %Y")
  end

  private

  def starts_on_first_day
    return if starts_on.blank? || starts_on.day == 1

    errors.add(:starts_on, "must be the first day of a month")
  end
end
