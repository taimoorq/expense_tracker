class PaySchedule < ApplicationRecord
  include PlanningTemplateMetadata
  include RecurringEntryTemplate
  include TemplateAccountLinkable

  belongs_to :user
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
    month_start = month_on.beginning_of_month
    month_end = month_on.end_of_month
    dates_for_cadence(month_start, month_end)
      .compact
      .map { |date| adjust_for_weekend(date) }
      .uniq
      .select { |date| active_on?(date) }
      .sort
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

  def dates_for_cadence(month_start, month_end)
    case cadence
    when "monthly"
      [ safe_month_date(month_start, day_of_month_one || first_pay_on.day) ]
    when "semimonthly"
      semimonthly_dates(month_start)
    when "weekly"
      recurring_dates(month_start, month_end, 7)
    when "biweekly"
      recurring_dates(month_start, month_end, 14)
    else
      []
    end
  end

  def semimonthly_dates(month_start)
    first_day = day_of_month_one || first_pay_on.day
    second_day = day_of_month_two || 22

    [
      safe_month_date(month_start, first_day),
      safe_month_date(month_start, second_day)
    ]
  end

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

  def recurring_dates(month_start, month_end, interval_days)
    current = first_pay_on
    while current < month_start
      current += interval_days
    end

    dates = []
    while current <= month_end
      dates << current
      current += interval_days
    end
    dates
  end

  def safe_month_date(month_start, day)
    Date.new(month_start.year, month_start.month, [ day.to_i, month_start.end_of_month.day ].min)
  end

  def adjust_for_weekend(date)
    return date if weekend_adjustment == "no_adjustment"
    return date - 1 if date.saturday? && weekend_adjustment == "previous_friday"
    return date - 2 if date.sunday? && weekend_adjustment == "previous_friday"
    return date + 2 if date.saturday? && weekend_adjustment == "next_monday"
    return date + 1 if date.sunday? && weekend_adjustment == "next_monday"

    date
  end

  def ends_on_not_before_first_pay_on
    return if ends_on.blank? || first_pay_on.blank?
    return if ends_on >= first_pay_on

    errors.add(:ends_on, "must be on or after the first pay date")
  end
end
