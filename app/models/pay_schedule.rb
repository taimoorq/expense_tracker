class PaySchedule < ApplicationRecord
  belongs_to :user

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

  scope :active_only, -> { where(active: true) }

  def pay_dates_for_month(month_on)
    month_start = month_on.beginning_of_month
    month_end = month_on.end_of_month

    dates = case cadence
    when "monthly"
      [ safe_month_date(month_start, day_of_month_one || first_pay_on.day) ]
    when "semimonthly"
      first_day = day_of_month_one || first_pay_on.day
      second_day = day_of_month_two || 22
      [
        safe_month_date(month_start, first_day),
        safe_month_date(month_start, second_day)
      ]
    when "weekly"
      recurring_dates(month_start, month_end, 7)
    when "biweekly"
      recurring_dates(month_start, month_end, 14)
    else
      []
    end

    dates.compact.map { |date| adjust_for_weekend(date) }.uniq.sort
  end

  def matches_entry?(entry, month_on:)
    return false if entry.blank? || entry.occurred_on.blank?
    return false unless comparable_text(entry.payee) == comparable_text(name)
    return false unless pay_dates_for_month(month_on).include?(entry.occurred_on)

    entry.source_file == "pay_schedule" || entry.income?
  end

  private

  def comparable_text(value)
    value.to_s.strip.downcase
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
end
