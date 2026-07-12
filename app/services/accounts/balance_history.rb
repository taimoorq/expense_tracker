module Accounts
  class BalanceHistory
    EMPTY_SUMMARY = {
      snapshot: nil,
      base_balance: 0.to_d,
      paid_delta: 0.to_d,
      planned_delta: 0.to_d,
      current_balance: 0.to_d,
      projected_balance: 0.to_d,
      balance_source: :none,
      balance_source_label: "No balance source",
      balance_source_record: nil,
      balance_source_recorded_on: nil,
      activity_through_on: nil,
      paid_entries_count: 0,
      planned_entries_count: 0,
      balance_available: false
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
      @summary ||= Accounts::BalanceResolver.new(account: account, as_of: as_of).call.to_h
    end

    def rows
      @rows ||= month_starts.map do |month_start|
        Accounts::PeriodBalance.new(
          account: account,
          period_start: month_start,
          period_end: month_start.end_of_month
        ).call.to_h.merge(month_on: month_start)
      end
    end

    def snapshots
      @snapshots ||= account.account_snapshots.select(&:persisted?).sort_by { |snapshot| [ snapshot.recorded_on, snapshot.created_at ] }
    end

    def month_starts
      @month_starts ||= begin
        dates = snapshots.map(&:recorded_on) +
          linked_entries.filter_map(&:occurred_on) +
          imported_activity_dates +
          institution_balance_source_dates +
          [ as_of ]
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

    def imported_activity_dates
      @imported_activity_dates ||= account.account_activities.pluck(:transaction_on)
    end

    def institution_balance_source_dates
      @institution_balance_source_dates ||= account.account_activity_imports.to_a
        .select(&:institution_balance?)
        .map { |activity_import| Accounts::BalanceSource.institution_balance_source_date(activity_import) }
    end

    def linked_entries
      @linked_entries ||= user.expense_entries
                            .where("source_account_id = :account_id OR destination_account_id = :account_id", account_id: account.id)
                            .where.not(occurred_on: nil)
                            .where(status: [ ExpenseEntry.statuses[:paid], ExpenseEntry.statuses[:planned] ])
                            .order(:occurred_on, :created_at)
                            .to_a
    end
  end
end
