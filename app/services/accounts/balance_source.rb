module Accounts
  class BalanceSource
    Result = Data.define(
      :account,
      :snapshot,
      :balance_source,
      :balance_source_label,
      :balance_source_record,
      :balance_source_recorded_on,
      :balance_available
    )

    def self.institution_balance_source_date(activity_import)
      activity_import.institution_balance_as_of || activity_import.ended_on || activity_import.created_at&.to_date || Date.current
    end

    def initialize(account:, as_of: Date.current, imported_activity_range: nil)
      @account = account
      @as_of = as_of
      @imported_activity_range = imported_activity_range
    end

    def call
      return institution_import_source(latest_institution_balance_import) if latest_institution_balance_import.present?
      return without_balance_source if latest_snapshot.blank?
      return imported_activity_source if imported_activity_after_snapshot?

      snapshot_source
    end

    private

    attr_reader :account, :as_of, :imported_activity_range

    def institution_import_source(activity_import)
      build_result(
        balance_source: :institution_import,
        balance_source_label: "Institution import",
        balance_source_record: activity_import,
        balance_source_recorded_on: self.class.institution_balance_source_date(activity_import),
        balance_available: true
      )
    end

    def imported_activity_source
      build_result(
        balance_source: :imported_activity,
        balance_source_label: "Imported activity",
        balance_source_record: latest_snapshot,
        balance_source_recorded_on: latest_snapshot.recorded_on,
        balance_available: true
      )
    end

    def snapshot_source
      build_result(
        balance_source: :snapshot,
        balance_source_label: "Manual snapshot",
        balance_source_record: latest_snapshot,
        balance_source_recorded_on: latest_snapshot.recorded_on,
        balance_available: true
      )
    end

    def without_balance_source
      build_result(
        balance_source: :none,
        balance_source_label: "No balance source",
        balance_source_record: nil,
        balance_source_recorded_on: nil,
        balance_available: false
      )
    end

    def build_result(**attributes)
      Result.new(account: account, snapshot: latest_snapshot, **attributes)
    end

    def latest_snapshot
      @latest_snapshot ||= account.account_snapshots
        .select { |snapshot| snapshot.persisted? && snapshot.recorded_on <= as_of }
        .max_by { |snapshot| [ snapshot.recorded_on, snapshot.created_at || Time.zone.at(0) ] }
    end

    def latest_institution_balance_import
      @latest_institution_balance_import ||= account.account_activity_imports.to_a
        .select(&:institution_balance?)
        .select { |activity_import| self.class.institution_balance_source_date(activity_import) <= as_of }
        .max_by { |activity_import| [ self.class.institution_balance_source_date(activity_import), activity_import.created_at || Time.zone.at(0) ] }
    end

    def imported_activity_after_snapshot?
      return false if latest_snapshot.blank?

      imported_activities_after_snapshot.exists?
    end

    def imported_activities_after_snapshot
      scope = account.account_activities.where(transaction_on: latest_snapshot.recorded_on.next_day..as_of)
      return scope if imported_activity_range.blank?

      scope.where(transaction_on: imported_activity_range)
    end
  end
end
