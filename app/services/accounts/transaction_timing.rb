module Accounts
  # Assumed times order date-only activity; they are never evidence of clearing.
  module TransactionTiming
    module_function

    def zone(workspace = nil, name: nil)
      ActiveSupport::TimeZone[name.presence || workspace&.time_zone || "UTC"] || Time.find_zone!("UTC")
    end

    def at(date:, incoming:, timestamp: nil, workspace: nil, zone_name: nil)
      return timestamp if timestamp.present?
      return if date.blank?

      local_zone = zone(workspace, name: zone_name)
      day = incoming ? date : date.next_day
      midnight = local_zone.local(day.year, day.month, day.day)
      incoming ? midnight : midnight - Rational(1, 1_000_000)
    end

    def key(date:, incoming:, timestamp: nil, workspace: nil, zone_name: nil, created_at: nil, id: nil)
      instant = at(date: date, incoming: incoming, timestamp: timestamp, workspace: workspace, zone_name: zone_name)
      [ date || Date.new(9999, 12, 31), instant&.to_r || 0, created_at&.to_r || 0, id.to_s ]
    end

    def parse(date:, clock:, zone_name:)
      raise ArgumentError, "Choose a date before entering a time." if date.blank?
      match = /\A(\d{2}):(\d{2})(?::(\d{2}))?\z/.match(clock.to_s)
      raise ArgumentError, "Enter a valid time." unless match

      hours, minutes, seconds = match.captures.map { |part| part.to_i }
      raise ArgumentError, "Enter a valid time." unless hours < 24 && minutes < 60 && seconds < 60

      local = Time.utc(date.year, date.month, date.day, hours, minutes, seconds)
      periods = zone(nil, name: zone_name).tzinfo.periods_for_local(local)
      raise ArgumentError, "This time does not exist because the clocks move forward. Choose another time." if periods.empty?
      raise ArgumentError, "This time occurs twice because the clocks move back. Choose an unambiguous time." if periods.size > 1

      (local - periods.first.utc_total_offset).utc
    end

    # Sort in SQL before pagination. Dates retain their existing month semantics.
    def sql(table:, date:, timestamp:, incoming:, descending: false, date_expression: nil, timestamp_expression: nil)
      direction = descending ? "DESC" : "ASC"
      date_expression ||= "#{table}.#{date}"
      timestamp_expression ||= "#{table}.#{timestamp}"
      timezone = "COALESCE(#{table}.timing_time_zone, (SELECT time_zone FROM budget_workspaces WHERE id = #{table}.budget_workspace_id), 'UTC')"
      assumed = "((#{date_expression} + CASE WHEN #{incoming} THEN TIME '00:00:00' ELSE TIME '23:59:59.999999' END) AT TIME ZONE #{timezone}) AT TIME ZONE 'UTC'"
      [ date_expression, "COALESCE(#{timestamp_expression}, #{assumed})", "#{table}.created_at", "#{table}.id" ].map { |expression| "#{expression} #{direction}" }.join(", ")
    end
  end
end
