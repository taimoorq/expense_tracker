class RecurrenceRule < ApplicationRecord
  enum :cadence, {
    weekly: "weekly",
    monthly: "monthly",
    yearly: "yearly",
    custom_months: "custom_months"
  }, prefix: true
  enum :weekend_policy, {
    none: "none",
    previous_friday: "previous_friday",
    next_monday: "next_monday"
  }, prefix: true

  belongs_to :planning_template
  has_many :recurrence_months, dependent: :restrict_with_error

  validates :planning_template_id, uniqueness: true
  validates :anchor_on, :starts_on, presence: true
  validates :interval_count, numericality: { only_integer: true, greater_than: 0 }
  validates :day_one, :day_two, inclusion: { in: 1..31 }, allow_nil: true
  validate :date_window_is_coherent

  private

  def date_window_is_coherent
    return if ends_on.blank? || starts_on.blank? || ends_on >= starts_on

    errors.add(:ends_on, "must be on or after starts on")
  end
end
