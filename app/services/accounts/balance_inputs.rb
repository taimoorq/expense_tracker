module Accounts
  class BalanceInputs
    ActivitySummary = Data.define(:account_delta, :through_on, :count)
    EMPTY_ACTIVITY_SUMMARY = ActivitySummary.new(account_delta: 0.to_d, through_on: nil, count: 0).freeze

    attr_reader :user

    def initialize(user:, accounts:, as_of: Date.current, load_activities: false)
      @user = user
      @accounts = Array(accounts)
      @as_of = as_of
      validate_ownership!
      preload_source_associations
      activities_by_account_id if load_activities
    end

    def balance_source_for(account)
      balance_sources.fetch(account.id)
    end

    def activity_summary_for(account)
      activity_summaries.fetch(account.id, EMPTY_ACTIVITY_SUMMARY)
    end

    def entries_for(account)
      entries_by_account_id.fetch(account.id, EMPTY_ARRAY)
    end

    def activities_for(account)
      activities_by_account_id.fetch(account.id, EMPTY_ARRAY)
    end

    def imports_for(account)
      account.account_activity_imports.to_a
    end

    private

    EMPTY_ARRAY = [].freeze

    attr_reader :accounts, :as_of

    def validate_ownership!
      return if accounts.all? { |account| account.user_id == user.id }

      raise ArgumentError, "all accounts must belong to the balance input user"
    end

    def preload_source_associations
      ActiveRecord::Associations::Preloader.new(
        records: accounts,
        associations: [ :account_snapshots, :account_activity_imports ]
      ).call
    end

    def balance_sources
      @balance_sources ||= accounts.index_by(&:id).transform_values do |account|
        Accounts::BalanceSource.new(
          account: account,
          as_of: as_of,
          imported_activity_exists: activity_summary_for(account).count.positive?
        ).call
      end
    end

    def activity_summaries
      @activity_summaries ||= begin
        source_dates = accounts.to_h do |account|
          [ account.id, candidate_source_date(account) ]
        end.compact_blank
        if defined?(@activities_by_account_id)
          source_dates.to_h do |account_id, source_date|
            rows = @activities_by_account_id.fetch(account_id, EMPTY_ARRAY).select do |activity|
              activity.transaction_on > source_date && activity.transaction_on <= as_of
            end
            [
              account_id,
              ActivitySummary.new(
                account_delta: rows.sum { |activity| activity.account_delta.to_d },
                through_on: rows.map(&:transaction_on).max,
                count: rows.size
              )
            ]
          end
        elsif source_dates.empty?
          {}
        else
          predicates = source_dates.map { "(account_id = ? AND transaction_on > ?)" }
          binds = source_dates.flat_map { |account_id, source_date| [ account_id, source_date ] }
          rows = user.account_activities
            .where(transaction_on: ..as_of)
            .where([ predicates.join(" OR "), *binds ])
            .group(:account_id)
            .pluck(
              :account_id,
              Arel.sql("COALESCE(SUM(account_delta), 0)"),
              Arel.sql("MAX(transaction_on)"),
              Arel.sql("COUNT(*)")
            )

          rows.to_h do |account_id, account_delta, through_on, count|
            [
              account_id,
              ActivitySummary.new(
                account_delta: account_delta.to_d,
                through_on: through_on,
                count: count.to_i
              )
            ]
          end
        end
      end
    end

    def activities_by_account_id
      @activities_by_account_id ||= begin
        grouped = Hash.new { |hash, account_id| hash[account_id] = [] }
        return grouped if accounts.empty?

        user.account_activities
          .where(account_id: accounts.map(&:id), transaction_on: ..as_of)
          .order(:transaction_on, :created_at)
          .each { |activity| grouped[activity.account_id] << activity }
        grouped
      end
    end

    def candidate_source_date(account)
      activity_import = Accounts::BalanceSource.latest_institution_balance_import_for(account, as_of: as_of)
      return Accounts::BalanceSource.institution_balance_source_date(activity_import) if activity_import.present?

      Accounts::BalanceSource.latest_snapshot_for(account, as_of: as_of)&.recorded_on
    end

    def entries_by_account_id
      @entries_by_account_id ||= begin
        grouped = Hash.new { |hash, account_id| hash[account_id] = [] }
        return grouped if accounts.empty?

        account_ids = accounts.map(&:id)
        user.expense_entries
          .where("source_account_id IN (:ids) OR destination_account_id IN (:ids)", ids: account_ids)
          .where.not(occurred_on: nil)
          .where(status: [ ExpenseEntry.statuses[:paid], ExpenseEntry.statuses[:planned] ])
          .order(:occurred_on, :created_at)
          .each do |entry|
            [ entry.source_account_id, entry.destination_account_id ].compact.uniq.each do |account_id|
              grouped[account_id] << entry if account_id.in?(account_ids)
            end
          end

        grouped
      end
    end
  end
end
