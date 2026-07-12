module Accounts
  class MovementTimeline
    RANGE_OPTIONS = {
      "30d" => "30 days",
      "90d" => "90 days",
      "6m" => "6 months",
      "12m" => "12 months",
      "all" => "All"
    }.freeze
    DEFAULT_RANGE = "6m"

    def initialize(account:, range: DEFAULT_RANGE, as_of: Date.current)
      @account = account
      @user = account.user
      @range = RANGE_OPTIONS.key?(range.to_s) ? range.to_s : DEFAULT_RANGE
      @as_of = as_of
    end

    def call
      {
        range: range,
        range_label: RANGE_OPTIONS.fetch(range),
        range_options: RANGE_OPTIONS,
        starts_on: range_start,
        ends_on: as_of,
        bucket_unit: bucket_unit,
        buckets: bucket_ranges.map { |bucket_range| build_bucket(bucket_range) }
      }
    end

    private

    attr_reader :account, :as_of, :range, :user

    def build_bucket(bucket_range)
      starts_on = bucket_range.begin
      ends_on = bucket_range.end
      actual_ends_on = [ ends_on, as_of ].min
      imported_rows = imported_activities.where(transaction_on: starts_on..actual_ends_on)
      imports = imports_for_period(starts_on..actual_ends_on, imported_rows)
      imported_source = imported_rows.exists?
      paid_rows = paid_entries.select { |entry| entry.occurred_on.between?(starts_on, actual_ends_on) }
      planned_rows = planned_entries.select { |entry| entry.occurred_on.between?(starts_on, ends_on) }
      actual_deltas = if imported_source
        imported_rows.pluck(:account_delta).map(&:to_d)
      else
        paid_rows.map { |entry| Accounts::EntryImpact.new(account: account, entry: entry).delta }
      end
      source = movement_source(imported_source: imported_source, paid_rows: paid_rows)
      balance = Accounts::PeriodBalance.new(
        account: account,
        period_start: starts_on,
        period_end: actual_ends_on
      ).call

      {
        label: bucket_label(starts_on, ends_on),
        starts_on: starts_on,
        ends_on: ends_on,
        actual_through_on: actual_ends_on,
        current_period: starts_on <= as_of && ends_on >= as_of,
        source: source,
        source_label: source_label(source),
        coverage: imported_source ? coverage_for(imports, imported_rows, starts_on..actual_ends_on) : no_import_coverage,
        incoming: movement_total(actual_deltas, :incoming, source: source),
        outgoing: movement_total(actual_deltas, :outgoing, source: source),
        net: movement_net(actual_deltas, source: source),
        planned_incoming: planned_total(planned_rows, :incoming),
        planned_outgoing: planned_total(planned_rows, :outgoing),
        ending_balance: display_balance(balance),
        projected_balance: display_projected_balance(balance),
        balance_available: balance.balance_available,
        activity_count: imported_source ? imported_rows.count : paid_rows.size,
        drilldown: {
          starts_on: starts_on.iso8601,
          ends_on: actual_ends_on.iso8601,
          source: source.to_s
        }
      }
    end

    def movement_source(imported_source:, paid_rows:)
      return :institution_activity if imported_source
      return :budget_entries if paid_rows.any?

      :none
    end

    def source_label(source)
      {
        institution_activity: "Institution activity",
        budget_entries: "Budget-linked activity",
        none: "No recorded activity"
      }.fetch(source)
    end

    def movement_total(deltas, direction, source:)
      return nil if source == :none

      selected = direction == :incoming ? deltas.select(&:positive?) : deltas.select(&:negative?)
      selected.sum(&:abs)
    end

    def movement_net(deltas, source:)
      return nil if source == :none

      deltas.sum
    end

    def planned_total(entries, direction)
      deltas = entries.map { |entry| Accounts::EntryImpact.new(account: account, entry: entry).delta }
      selected = direction == :incoming ? deltas.select(&:positive?) : deltas.select(&:negative?)
      selected.sum(&:abs)
    end

    def display_balance(balance)
      return nil unless balance.balance_available

      account.liability? ? balance.current_balance.to_d.abs : balance.current_balance.to_d
    end

    def display_projected_balance(balance)
      return nil unless balance.balance_available

      account.liability? ? balance.projected_balance.to_d.abs : balance.projected_balance.to_d
    end

    def coverage_for(imports, imported_rows, period)
      return { status: :not_applicable, starts_on: nil, ends_on: nil } if imports.empty?

      intervals = imports.filter_map do |activity_import|
        next if activity_import.started_on.blank? || activity_import.ended_on.blank?

        [ [ activity_import.started_on, period.begin ].max, [ activity_import.ended_on, period.end ].min ]
      end.select { |starts_on, ends_on| starts_on <= ends_on }
      if intervals.empty?
        return {
          status: :partial,
          starts_on: imported_rows.minimum(:transaction_on),
          ends_on: imported_rows.maximum(:transaction_on)
        }
      end

      merged = intervals.sort_by(&:first).each_with_object([]) do |interval, memo|
        if memo.empty? || interval.first > memo.last.last.next_day
          memo << interval
        else
          memo[-1] = [ memo.last.first, [ memo.last.last, interval.last ].max ]
        end
      end
      fully_covered = merged.one? && merged.first.first <= period.begin && merged.first.last >= period.end

      {
        status: fully_covered ? :complete : :partial,
        starts_on: merged.first.first,
        ends_on: merged.last.last
      }
    end

    def no_import_coverage
      { status: :not_applicable, starts_on: nil, ends_on: nil }
    end

    def bucket_ranges
      @bucket_ranges ||= case bucket_unit
      when :day
        daily_bucket_ranges
      when :week
        weekly_bucket_ranges
      when :quarter
        quarterly_bucket_ranges
      else
        monthly_bucket_ranges
      end
    end

    def daily_bucket_ranges
      (range_start..as_of).map { |date| date..date }
    end

    def weekly_bucket_ranges
      ranges = []
      cursor = range_start
      while cursor <= as_of
        week_end = [ cursor.end_of_week, as_of ].min
        ranges << (cursor..week_end)
        cursor = week_end.next_day
      end
      ranges
    end

    def monthly_bucket_ranges
      ranges = []
      cursor = range_start.beginning_of_month
      final_month = as_of.beginning_of_month
      while cursor <= final_month
        ranges << (cursor..cursor.end_of_month)
        cursor = cursor.next_month
      end
      ranges
    end

    def quarterly_bucket_ranges
      ranges = []
      cursor = range_start.beginning_of_quarter
      final_quarter = as_of.beginning_of_quarter
      while cursor <= final_quarter
        ranges << (cursor..cursor.end_of_quarter)
        cursor = cursor.next_quarter
      end
      ranges
    end

    def bucket_label(starts_on, ends_on)
      case bucket_unit
      when :day
        starts_on.strftime("%b %-d")
      when :week
        "#{starts_on.strftime('%b %-d')}–#{ends_on.strftime('%b %-d')}"
      when :quarter
        "Q#{((starts_on.month - 1) / 3) + 1} #{starts_on.year}"
      else
        starts_on.strftime("%b %Y")
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

    def range_start
      @range_start ||= case range
      when "30d" then as_of - 29.days
      when "90d" then as_of - 89.days
      when "12m" then (as_of - 11.months).beginning_of_month
      when "all" then earliest_activity_on
      else (as_of - 5.months).beginning_of_month
      end
    end

    def all_month_count
      ((as_of.year * 12) + as_of.month) - ((earliest_activity_on.year * 12) + earliest_activity_on.month) + 1
    end

    def earliest_activity_on
      @earliest_activity_on ||= [
        account.account_snapshots.minimum(:recorded_on),
        imported_activities.minimum(:transaction_on),
        account.account_activity_imports.minimum(:started_on),
        linked_entries.filter_map(&:occurred_on).min,
        as_of
      ].compact.min
    end

    def imports_for_period(period, imported_rows)
      overlapping = account.account_activity_imports.where("started_on <= ? AND ended_on >= ?", period.end, period.begin)
      row_imports = account.account_activity_imports.where(id: imported_rows.select(:account_activity_import_id))
      (overlapping.to_a + row_imports.to_a).uniq(&:id)
    end

    def imported_activities
      @imported_activities ||= account.account_activities
    end

    def linked_entries
      @linked_entries ||= user.expense_entries
        .where("source_account_id = :account_id OR destination_account_id = :account_id", account_id: account.id)
        .where.not(occurred_on: nil)
        .where(status: [ ExpenseEntry.statuses[:paid], ExpenseEntry.statuses[:planned] ])
        .order(:occurred_on, :created_at)
        .to_a
    end

    def paid_entries
      @paid_entries ||= linked_entries.select(&:paid?)
    end

    def planned_entries
      @planned_entries ||= linked_entries.select(&:planned?)
    end
  end
end
