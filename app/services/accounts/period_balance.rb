module Accounts
  class PeriodBalance
    Result = Data.define(
      :account,
      :period_start,
      :period_end,
      :snapshot,
      :balance_source,
      :balance_source_label,
      :balance_source_record,
      :balance_source_recorded_on,
      :activity_through_on,
      :base_balance,
      :starting_balance,
      :paid_delta,
      :planned_delta,
      :current_balance,
      :projected_balance,
      :paid_entries_count,
      :planned_entries_count,
      :balance_available
    )

    def initialize(account:, period_start:, period_end:)
      @account = account
      @user = account.user
      @period_start = period_start
      @period_end = period_end
    end

    def call
      case balance_source.balance_source
      when :institution_import
        from_institution_import
      when :imported_activity
        from_imported_activity
      when :snapshot
        from_manual_snapshot
      else
        without_balance_source
      end
    end

    private

    attr_reader :account, :period_end, :period_start, :user

    def from_institution_import
      activity_import = balance_source.balance_source_record

      build_imported_result(
        base_balance: activity_import.institution_balance.to_d
      )
    end

    def from_imported_activity
      build_imported_result(
        base_balance: balance_source.snapshot.balance.to_d
      )
    end

    def build_imported_result(base_balance:)
      source_date = balance_source.balance_source_recorded_on
      activity_rows = imported_activity_rows(source_date)
      paid_delta = activity_rows.sum(:account_delta).to_d
      planned_entries_for_period = planned_entries_after_source(source_date)
      planned_delta = totals_for(planned_entries_for_period)
      starting_balance = imported_starting_balance(base_balance: base_balance, source_date: source_date)
      current_balance = starting_balance + paid_delta

      build_result(
        activity_through_on: activity_rows.maximum(:transaction_on),
        base_balance: base_balance,
        starting_balance: starting_balance,
        paid_delta: paid_delta,
        planned_delta: planned_delta,
        current_balance: current_balance,
        projected_balance: current_balance + planned_delta,
        paid_entries_count: activity_rows.count,
        planned_entries_count: planned_entries_for_period.size,
        balance_available: true
      )
    end

    def from_manual_snapshot
      source_date = balance_source.balance_source_recorded_on
      base_balance = balance_source.snapshot.balance.to_d
      paid_entries_for_period = paid_entries_after_source(source_date)
      paid_delta = totals_for(paid_entries_for_period)
      planned_entries_for_period = planned_entries_after_source(source_date)
      planned_delta = totals_for(planned_entries_for_period)
      starting_balance = linked_starting_balance(base_balance: base_balance, source_date: source_date)
      current_balance = starting_balance + paid_delta

      build_result(
        activity_through_on: nil,
        base_balance: base_balance,
        starting_balance: starting_balance,
        paid_delta: paid_delta,
        planned_delta: planned_delta,
        current_balance: current_balance,
        projected_balance: current_balance + planned_delta,
        paid_entries_count: paid_entries_for_period.size,
        planned_entries_count: planned_entries_for_period.size,
        balance_available: true
      )
    end

    def without_balance_source
      build_result(
        activity_through_on: nil,
        base_balance: 0.to_d,
        starting_balance: 0.to_d,
        paid_delta: 0.to_d,
        planned_delta: 0.to_d,
        current_balance: 0.to_d,
        projected_balance: 0.to_d,
        paid_entries_count: 0,
        planned_entries_count: 0,
        balance_available: false
      )
    end

    def build_result(**attributes)
      Result.new(
        account: account,
        period_start: period_start,
        period_end: period_end,
        snapshot: balance_source.snapshot,
        balance_source: balance_source.balance_source,
        balance_source_label: balance_source.balance_source_label,
        balance_source_record: balance_source.balance_source_record,
        balance_source_recorded_on: balance_source.balance_source_recorded_on,
        **attributes
      )
    end

    def balance_source
      @balance_source ||= Accounts::BalanceSource.new(
        account: account,
        as_of: period_end,
        imported_activity_range: period_start..period_end
      ).call
    end

    def imported_starting_balance(base_balance:, source_date:)
      return base_balance if source_date >= period_start

      base_balance + imported_delta_between(source_date.next_day, period_start.prev_day)
    end

    def linked_starting_balance(base_balance:, source_date:)
      return base_balance if source_date >= period_start

      base_balance + totals_for(paid_entries_between(source_date.next_day, period_start.prev_day))
    end

    def imported_activity_rows(source_date)
      start_on = activity_start_on(source_date)
      return account.account_activities.none if start_on > period_end

      account.account_activities.where(transaction_on: start_on..period_end)
    end

    def imported_delta_between(start_on, end_on)
      return 0.to_d if start_on > end_on

      account.account_activities.where(transaction_on: start_on..end_on).sum(:account_delta).to_d
    end

    def paid_entries_after_source(source_date)
      paid_entries_between(activity_start_on(source_date), period_end)
    end

    def planned_entries_after_source(source_date)
      planned_entries_between(activity_start_on(source_date), period_end)
    end

    def activity_start_on(source_date)
      [ source_date.next_day, period_start ].max
    end

    def paid_entries_between(start_on, end_on)
      return [] if start_on > end_on

      paid_entries.select { |entry| entry.occurred_on >= start_on && entry.occurred_on <= end_on }
    end

    def planned_entries_between(start_on, end_on)
      return [] if start_on > end_on

      planned_entries.select { |entry| entry.occurred_on >= start_on && entry.occurred_on <= end_on }
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

    def totals_for(entries)
      entries.sum { |entry| account.account_delta_for(entry) }
    end
  end
end
