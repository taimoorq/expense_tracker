module Recurring
  class PayScheduleCalendar
    def initialize(schedule:, month_on:)
      @schedule = schedule
      @month_start = month_on.beginning_of_month
      @month_end = month_on.end_of_month
    end

    def call
      dates_for_cadence
        .compact
        .map { |date| adjust_for_weekend(date) }
        .uniq
        .select { |date| schedule.active_on?(date) }
        .sort
    end

    private

    attr_reader :schedule, :month_start, :month_end

    def dates_for_cadence
      case schedule.cadence
      when "monthly"
        [ safe_month_date(schedule.day_of_month_one || schedule.first_pay_on.day) ]
      when "semimonthly"
        semimonthly_dates
      when "weekly"
        recurring_dates(7)
      when "biweekly"
        recurring_dates(14)
      else
        []
      end
    end

    def semimonthly_dates
      first_day = schedule.day_of_month_one || schedule.first_pay_on.day
      second_day = schedule.day_of_month_two || 22

      [ safe_month_date(first_day), safe_month_date(second_day) ]
    end

    def recurring_dates(interval_days)
      current = schedule.first_pay_on
      current += interval_days while current < month_start

      dates = []
      while current <= month_end
        dates << current
        current += interval_days
      end
      dates
    end

    def safe_month_date(day)
      Date.new(month_start.year, month_start.month, [ day.to_i, month_end.day ].min)
    end

    def adjust_for_weekend(date)
      return date if schedule.no_adjustment?
      return date - 1 if date.saturday? && schedule.previous_friday?
      return date - 2 if date.sunday? && schedule.previous_friday?
      return date + 2 if date.saturday? && schedule.next_monday?
      return date + 1 if date.sunday? && schedule.next_monday?

      date
    end
  end
end
