module Accounts
  class BalanceHistory
    EMPTY_SUMMARY = {
      snapshot: nil,
      base_balance: 0.to_d,
      paid_delta: 0.to_d,
      planned_delta: 0.to_d,
      current_balance: 0.to_d,
      projected_balance: 0.to_d,
      paid_entries_count: 0,
      planned_entries_count: 0
    }.freeze

    def initialize(account:, as_of: Date.current)
      @account = account
      @user = account.user
      @as_of = as_of
    end

    def call
      {
        summary: summary,
        rows: rows
      }
    end

    private

    attr_reader :account, :user, :as_of

    def summary
      @summary ||= begin
        paid_delta = totals_for(paid_entries_after_snapshot)
        planned_delta = totals_for(planned_entries_after_as_of)
        base_balance = latest_snapshot&.balance.to_d

        {
          snapshot: latest_snapshot,
          base_balance: base_balance,
          paid_delta: paid_delta,
          planned_delta: planned_delta,
          current_balance: base_balance + paid_delta,
          projected_balance: base_balance + paid_delta + planned_delta,
          paid_entries_count: paid_entries_after_snapshot.size,
          planned_entries_count: planned_entries_after_as_of.size
        }
      end
    end

    def rows
      @rows ||= month_starts.map do |month_start|
        build_month_row(month_start)
      end
    end

    def build_month_row(month_start)
      month_end = month_start.end_of_month
      snapshot = snapshot_on_or_before(month_end)
      starts_from_month_snapshot = snapshot.present? && snapshot.recorded_on >= month_start
      activity_start = starts_from_month_snapshot ? snapshot.recorded_on : month_start
      starting_balance = starts_from_month_snapshot ? snapshot.balance.to_d : balance_before(month_start)
      paid_entries_for_month = paid_entries.select { |entry| entry.occurred_on > activity_start && entry.occurred_on <= month_end }
      planned_entries_for_month = planned_entries.select { |entry| entry.occurred_on > activity_start && entry.occurred_on <= month_end }
      paid_delta = totals_for(paid_entries_for_month)
      planned_delta = totals_for(planned_entries_for_month)
      current_balance = starting_balance + paid_delta

      {
        month_on: month_start,
        starting_balance: starting_balance,
        paid_delta: paid_delta,
        planned_delta: planned_delta,
        current_balance: current_balance,
        projected_balance: current_balance + planned_delta,
        paid_entries_count: paid_entries_for_month.size,
        planned_entries_count: planned_entries_for_month.size
      }
    end

    def balance_before(date)
      snapshot = snapshot_before(date)
      base_date = snapshot&.recorded_on
      base_balance = snapshot&.balance.to_d

      base_balance + totals_for(
        paid_entries.select do |entry|
          entry.occurred_on < date && (base_date.blank? || entry.occurred_on > base_date)
        end
      )
    end

    def snapshot_before(date)
      snapshots.select { |candidate| candidate.recorded_on < date }.max_by { |candidate| [ candidate.recorded_on, candidate.created_at ] }
    end

    def snapshot_on_or_before(date)
      snapshots.select { |candidate| candidate.recorded_on <= date }.max_by { |candidate| [ candidate.recorded_on, candidate.created_at ] }
    end

    def latest_snapshot
      @latest_snapshot ||= account.latest_snapshot
    end

    def snapshots
      @snapshots ||= account.account_snapshots.select(&:persisted?).sort_by { |snapshot| [ snapshot.recorded_on, snapshot.created_at ] }
    end

    def month_starts
      @month_starts ||= begin
        dates = snapshots.map(&:recorded_on) + linked_entries.filter_map(&:occurred_on) + [ as_of ]
        cursor = (dates.compact.min || as_of).beginning_of_month
        last_month = (dates.compact.max || as_of).beginning_of_month
        months = []

        while cursor <= last_month
          months << cursor
          cursor = cursor.next_month
        end

        months
      end
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

    def paid_entries_after_snapshot
      @paid_entries_after_snapshot ||= paid_entries.select do |entry|
        entry.occurred_on <= as_of && (latest_snapshot.blank? || entry.occurred_on > latest_snapshot.recorded_on)
      end
    end

    def planned_entries_after_as_of
      @planned_entries_after_as_of ||= planned_entries.select { |entry| entry.occurred_on >= as_of }
    end

    def totals_for(entries)
      entries.sum { |entry| account.account_delta_for(entry) }
    end
  end
end
