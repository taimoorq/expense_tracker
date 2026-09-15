module Platform
  module Backup
    class ScheduleCalculator
      SEARCH_LIMIT_DAYS = 400

      def self.next_at(schedule, after:)
        new(schedule).next_at(after: after)
      end

      def initialize(schedule)
        @schedule = schedule
        @zone = ActiveSupport::TimeZone[schedule.time_zone]
        raise ArgumentError, "Unsupported backup time zone" unless zone
      end

      def next_at(after:)
        after = after.in_time_zone("UTC")
        local_date = after.in_time_zone(zone).to_date

        SEARCH_LIMIT_DAYS.times do |offset|
          date = local_date + offset.days
          next unless eligible_date?(date)

          candidate = zone.local(date.year, date.month, date.day, schedule.local_hour, schedule.local_minute)
          return candidate.utc if candidate.utc > after
        end

        raise ArgumentError, "Could not calculate the next backup time"
      end

      private

      attr_reader :schedule, :zone

      def eligible_date?(date)
        return true if schedule.cadence_daily?
        return date.wday == schedule.weekday if schedule.cadence_weekly?

        date.day == schedule.day_of_month
      end
    end
  end
end
