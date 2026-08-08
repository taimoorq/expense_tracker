module Accounts
  class MovementWindow
    RANGE_OPTIONS = {
      "30d" => "30 days",
      "90d" => "90 days",
      "6m" => "6 months",
      "12m" => "12 months",
      "all" => "All"
    }.freeze
    DEFAULT_RANGE = "6m"

    attr_reader :as_of, :earliest_on, :range

    def initialize(range:, as_of:, earliest_on:)
      @range = RANGE_OPTIONS.key?(range.to_s) ? range.to_s : DEFAULT_RANGE
      @as_of = as_of.to_date
      @earliest_on = (earliest_on || @as_of).to_date
    end

    def range_label
      RANGE_OPTIONS.fetch(range)
    end

    def starts_on
      @starts_on ||= case range
      when "30d" then as_of - 29.days
      when "90d" then as_of - 89.days
      when "12m" then (as_of - 11.months).beginning_of_month
      when "all" then earliest_on
      else (as_of - 5.months).beginning_of_month
      end
    end

    def bucket_unit
      @bucket_unit ||= case range
      when "30d" then :day
      when "90d" then :week
      when "all" then all_month_count > 24 ? :quarter : :month
      else :month
      end
    end

    def bucket_ranges
      @bucket_ranges ||= case bucket_unit
      when :day then daily_bucket_ranges
      when :week then weekly_bucket_ranges
      when :quarter then quarterly_bucket_ranges
      else monthly_bucket_ranges
      end
    end

    private

    def all_month_count
      ((as_of.year * 12) + as_of.month) - ((earliest_on.year * 12) + earliest_on.month) + 1
    end

    def daily_bucket_ranges
      (starts_on..as_of).map { |date| date..date }
    end

    def weekly_bucket_ranges
      build_ranges(starts_on) { |cursor| [ cursor.end_of_week, as_of ].min }
    end

    def monthly_bucket_ranges
      build_ranges(starts_on.beginning_of_month) { |cursor| cursor.end_of_month }
    end

    def quarterly_bucket_ranges
      build_ranges(starts_on.beginning_of_quarter) { |cursor| cursor.end_of_quarter }
    end

    def build_ranges(first_start)
      ranges = []
      cursor = first_start
      while cursor <= as_of
        ending = yield(cursor)
        ranges << (cursor..ending)
        cursor = ending.next_day
      end
      ranges
    end
  end
end
