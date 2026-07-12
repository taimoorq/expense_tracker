module Accounts
  class BalanceResolver
    Result = Data.define(
      :account,
      :snapshot,
      :balance_source,
      :balance_source_label,
      :balance_source_record,
      :balance_source_recorded_on,
      :activity_through_on,
      :base_balance,
      :paid_delta,
      :planned_delta,
      :current_balance,
      :projected_balance,
      :paid_entries_count,
      :planned_entries_count,
      :balance_available
    )

    def initialize(account:, as_of: Date.current)
      @account = account
      @user = account.user
      @as_of = as_of
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

    attr_reader :account, :as_of, :user

    def from_institution_import
      activity_import = balance_source.balance_source_record
      source_date = balance_source.balance_source_recorded_on
      activity_rows = imported_activities_after(source_date)
      activity_delta = activity_rows.sum(:account_delta).to_d
      activity_through_on = activity_rows.maximum(:transaction_on)
      base_balance = activity_import.institution_balance.to_d
      current_balance = base_balance + activity_delta
      planned_delta = totals_for(planned_entries_after_as_of)

      build_result(
        balance_source: :institution_import,
        balance_source_label: "Institution import",
        balance_source_record: activity_import,
        balance_source_recorded_on: source_date,
        activity_through_on: activity_through_on,
        base_balance: base_balance,
        paid_delta: activity_delta,
        planned_delta: planned_delta,
        current_balance: current_balance,
        projected_balance: current_balance + planned_delta,
        paid_entries_count: activity_rows.count,
        planned_entries_count: planned_entries_after_as_of.size,
        balance_available: true
      )
    end

    def from_imported_activity
      source_date = balance_source.balance_source_recorded_on
      activity_rows = imported_activities_after(source_date)
      activity_delta = activity_rows.sum(:account_delta).to_d
      activity_through_on = activity_rows.maximum(:transaction_on)
      base_balance = balance_source.snapshot.balance.to_d
      current_balance = base_balance + activity_delta
      planned_delta = totals_for(planned_entries_after_as_of)

      build_result(
        balance_source: :imported_activity,
        balance_source_label: "Imported activity",
        balance_source_record: balance_source.balance_source_record,
        balance_source_recorded_on: source_date,
        activity_through_on: activity_through_on,
        base_balance: base_balance,
        paid_delta: activity_delta,
        planned_delta: planned_delta,
        current_balance: current_balance,
        projected_balance: current_balance + planned_delta,
        paid_entries_count: activity_rows.count,
        planned_entries_count: planned_entries_after_as_of.size,
        balance_available: true
      )
    end

    def from_manual_snapshot
      paid_delta = totals_for(paid_entries_after_snapshot)
      planned_delta = totals_for(planned_entries_after_as_of)
      base_balance = balance_source.snapshot.balance.to_d
      current_balance = base_balance + paid_delta

      build_result(
        balance_source: :snapshot,
        balance_source_label: "Manual snapshot",
        balance_source_record: balance_source.balance_source_record,
        balance_source_recorded_on: balance_source.balance_source_recorded_on,
        activity_through_on: nil,
        base_balance: base_balance,
        paid_delta: paid_delta,
        planned_delta: planned_delta,
        current_balance: current_balance,
        projected_balance: current_balance + planned_delta,
        paid_entries_count: paid_entries_after_snapshot.size,
        planned_entries_count: planned_entries_after_as_of.size,
        balance_available: true
      )
    end

    def without_balance_source
      build_result(
        balance_source: :none,
        balance_source_label: "No balance source",
        balance_source_record: nil,
        balance_source_recorded_on: nil,
        activity_through_on: nil,
        base_balance: 0.to_d,
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
        snapshot: balance_source.snapshot,
        **attributes
      )
    end

    def balance_source
      @balance_source ||= Accounts::BalanceSource.new(account: account, as_of: as_of).call
    end

    def imported_activities_after(date)
      return account.account_activities.none if date.blank?

      account.account_activities.where(transaction_on: (date.next_day)..as_of)
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
        entry.occurred_on <= as_of && entry.occurred_on > balance_source.balance_source_recorded_on
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
