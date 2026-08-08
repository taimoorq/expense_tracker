module Planning
  class OccurrenceSchedule
    Occurrence = Data.define(:scheduled_on, :slot_key)

    def self.call(rule:, period:)
      new(rule: rule, period: period).call
    end

    def initialize(rule:, period:)
      @rule = rule
      @period = period
    end

    def call
      base_occurrences.filter_map do |date, slot_key|
        next unless rule_window.cover?(date)

        Occurrence.new(scheduled_on: adjust_weekend(date), slot_key: slot_key)
      end.uniq.sort_by { |occurrence| [ occurrence.scheduled_on, occurrence.slot_key ] }
    end

    private

    attr_reader :period, :rule

    def base_occurrences
      case rule.cadence
      when "weekly"
        weekly_occurrences
      when "monthly"
        monthly_occurrences
      when "yearly"
        yearly_occurrences
      when "custom_months"
        custom_month_occurrences
      else
        []
      end
    end

    def weekly_occurrences
      date = rule.anchor_on
      step = rule.interval_count * 7
      date += step while date < period.starts_on
      occurrences = []
      while date <= period.starts_on.end_of_month
        occurrences << [ date, "anchor-#{date.iso8601}" ]
        date += step
      end
      occurrences
    end

    def monthly_occurrences
      return [] unless interval_month?

      [ [ rule.day_one || rule.anchor_on.day, "day-one" ], [ rule.day_two, "day-two" ] ]
        .filter_map { |day, slot| [ safe_date(day), slot ] if day.present? }
    end

    def yearly_occurrences
      return [] unless interval_year? && period.starts_on.month == rule.anchor_on.month

      [ [ safe_date(rule.day_one || rule.anchor_on.day), "yearly" ] ]
    end

    def custom_month_occurrences
      return [] unless rule.recurrence_months.exists?(month_number: period.starts_on.month)
      return [] unless interval_month?

      monthly_occurrences
    end

    def interval_month?
      month_distance = (period.starts_on.year * 12 + period.starts_on.month) - (rule.anchor_on.year * 12 + rule.anchor_on.month)
      month_distance >= 0 && (month_distance % rule.interval_count).zero?
    end

    def interval_year?
      year_distance = period.starts_on.year - rule.anchor_on.year
      year_distance >= 0 && (year_distance % rule.interval_count).zero?
    end

    def safe_date(day)
      Date.new(period.starts_on.year, period.starts_on.month, [ day, period.starts_on.end_of_month.day ].min)
    end

    def rule_window
      rule.starts_on..(rule.ends_on || Date.new(9999, 12, 31))
    end

    def adjust_weekend(date)
      return date if rule.weekend_policy_none?
      return date - 1 if date.saturday? && rule.weekend_policy_previous_friday?
      return date - 2 if date.sunday? && rule.weekend_policy_previous_friday?
      return date + 2 if date.saturday? && rule.weekend_policy_next_monday?
      return date + 1 if date.sunday? && rule.weekend_policy_next_monday?

      date
    end
  end
end
