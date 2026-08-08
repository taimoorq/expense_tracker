class PaySchedule < ApplicationRecord
  include LegacyWorkspaceOwned
  include PlanningTemplateMetadata
  include RecurringEntryTemplate
  include TemplateAccountLinkable

  belongs_to :user
  belongs_to :budget_workspace, optional: true
  belongs_to :linked_account, class_name: "Account", optional: true
  template_account_association :linked_account
  planning_template_metadata(
    type_key: :pay_schedule,
    source_file: "pay_schedule",
    param_key: :pay_schedule,
    recurring_source: true,
    wizard_sections: %w[income],
    permitted_attributes: [ :name, :cadence, :amount, :first_pay_on, :ends_on, :day_of_month_one, :day_of_month_two, :weekend_adjustment, :linked_account_id, :account, :active ]
  )

  enum :cadence, {
    weekly: 0,
    biweekly: 1,
    semimonthly: 2,
    monthly: 3
  }

  enum :weekend_adjustment, {
    no_adjustment: 0,
    previous_friday: 1,
    next_monday: 2
  }

  validates :name, presence: true
  validates :amount, presence: true
  validates :amount, numericality: { greater_than: 0 }, allow_nil: true
  validates :first_pay_on, presence: true
  validate :ends_on_not_before_first_pay_on

  scope :active_only, -> { where(active: true).order(:name) }
  scope :active_during_month, ->(month_on) {
    month_start = month_on.to_date.beginning_of_month
    month_end = month_on.to_date.end_of_month

    active_only
      .where("first_pay_on <= ?", month_end)
      .where("ends_on IS NULL OR ends_on >= ?", month_start)
  }

  def pay_dates_for_month(month_on)
    Recurring::PayScheduleCalendar.new(schedule: self, month_on: month_on).call
  end

  def matches_entry?(entry, month_on:)
    matches_entry_for_month?(entry, month_on: month_on)
  end

  def recurring_month_occurrences(month_on)
    pay_dates_for_month(month_on)
  end

  def active_on?(date)
    date = date.to_date
    return false unless active?
    return false if first_pay_on.present? && date < first_pay_on
    return false if ends_on.present? && date > ends_on

    true
  end

  def lifecycle_status(on: Date.current)
    date = on.to_date
    return :disabled unless active?
    return :upcoming if first_pay_on.present? && first_pay_on > date
    return :ended if ends_on.present? && ends_on < date
    return :ending if ends_on.present?

    :current
  end

  private

  def generated_entry_amount(month_on:, occurred_on:)
    amount
  end

  def generated_entry_section
    :income
  end

  def generated_entry_category
    "Paycheck"
  end

  def generated_entry_notes(month_on:, occurred_on:)
    "Generated from pay schedule"
  end

  def strict_matching_amount?
    true
  end

  def ends_on_not_before_first_pay_on
    return if ends_on.blank? || first_pay_on.blank?
    return if ends_on >= first_pay_on

    errors.add(:ends_on, "must be on or after the first pay date")
  end
end
