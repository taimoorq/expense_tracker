module Accounts
  class Summary
    def initialize(user:, include_trend: false)
      @user = user
      @include_trend = include_trend
    end

    def call
      {
        accounts: accounts,
        net_worth_accounts: net_worth_accounts,
        account_balances: account_balances,
        account_balance_rows: account_balance_rows,
        assets_total: assets_total,
        liabilities_total: liabilities_total,
        net_worth_total: assets_total - liabilities_total,
        latest_snapshot: latest_snapshot,
        latest_balance_source: latest_balance_source,
        accounts_with_balance_sources_count: accounts_with_balance_sources_count,
        accounts_missing_balance_sources_count: accounts.size - accounts_with_balance_sources_count,
        accounts_with_snapshots_count: accounts_with_snapshots_count,
        accounts_missing_snapshots_count: accounts.size - accounts_with_snapshots_count,
        trend_labels: include_trend? ? trend_labels : [],
        trend_values: include_trend? ? trend_values : [],
        trend_rows: include_trend? ? trend_rows : [],
        calculation_version: target_reads? ? Budgeting::PeriodSummary::CALCULATION_VERSION : "legacy-compatible-v1"
      }
    end

    private

    attr_reader :user

    def include_trend?
      @include_trend
    end

    def accounts
      @accounts ||= user.accounts.includes(:budget_workspace, :account_snapshots, :account_activity_imports).active_first.to_a
    end

    def net_worth_accounts
      @net_worth_accounts ||= accounts.select(&:include_in_net_worth)
    end

    def assets_total
      @assets_total ||= net_worth_accounts.select(&:asset?).sum do |account|
        balance = account_balance_for(account)
        balance.balance_available ? balance.current_balance : 0.to_d
      end
    end

    def liabilities_total
      @liabilities_total ||= net_worth_accounts.select(&:liability?).sum do |account|
        balance = account_balance_for(account)
        balance.balance_available ? balance.current_balance.abs : 0.to_d
      end
    end

    def latest_snapshot
      @latest_snapshot ||= user.account_snapshots
        .joins(:account)
        .merge(Account.where(user: user))
        .order(recorded_on: :desc, created_at: :desc)
        .first
    end

    def accounts_with_snapshots_count
      @accounts_with_snapshots_count ||= accounts.count(&:latest_snapshot)
    end

    def account_balances
      @account_balances ||= begin
        target_accounts, legacy_accounts = accounts.partition { |account| account.budget_workspace&.target_reads_enabled? }
        target = Accounts::TargetBalanceBatch.call(accounts: target_accounts)
        legacy = legacy_accounts.index_with do |account|
          Accounts::BalanceResolver.new(account: account, inputs: balance_inputs).call
        end
        target.merge(legacy)
      end
    end

    def balance_inputs
      @balance_inputs ||= Accounts::BalanceInputs.new(user: user, accounts: accounts)
    end

    def account_balance_rows
      @account_balance_rows ||= accounts.map do |account|
        balance = account_balance_for(account)
        imported_activity = imported_activity_summary_for(account)
        {
          account: account,
          current_balance: balance.current_balance,
          projected_balance: balance.projected_balance,
          source_label: balance.balance_source_label,
          source_type: balance.balance_source,
          source_date: balance.balance_source_recorded_on,
          activity_through_on: balance.activity_through_on,
          last_updated_on: balance.activity_through_on || balance.balance_source_recorded_on || imported_activity.fetch(:through_on),
          source_record: balance.balance_source_record,
          activity_delta: balance.paid_delta,
          planned_delta: balance.planned_delta,
          activity_count: balance.paid_entries_count,
          planned_entries_count: balance.planned_entries_count,
          imported_activity_count: imported_activity.fetch(:count),
          imported_activity_through_on: imported_activity.fetch(:through_on),
          balance_available: balance.balance_available
        }
      end
    end

    def imported_activity_summary_for(account)
      imported_activity_summaries.fetch(account.id, { count: 0, through_on: nil })
    end

    def imported_activity_summaries
      @imported_activity_summaries ||= user.account_activities
        .where(account_id: accounts.map(&:id))
        .group(:account_id)
        .pluck(:account_id, Arel.sql("COUNT(*)"), Arel.sql("MAX(transaction_on)"))
        .to_h { |account_id, count, through_on| [ account_id, { count: count.to_i, through_on: through_on } ] }
    end

    def account_balance_for(account)
      account_balances.fetch(account)
    end

    def latest_balance_source
      @latest_balance_source ||= account_balances.values
        .select(&:balance_available)
        .max_by { |balance| [ balance.activity_through_on || balance.balance_source_recorded_on, balance.balance_source_record&.created_at || Time.zone.at(0) ] }
    end

    def accounts_with_balance_sources_count
      @accounts_with_balance_sources_count ||= account_balances.values.count(&:balance_available)
    end

    def trend_labels
      trend_data.first
    end

    def trend_values
      trend_data.last
    end

    def trend_data
      @trend_data ||= begin
        return target_trend_data if target_reads?

        dated_snapshots = net_worth_accounts.index_with { |account| account.account_snapshots.sort_by(&:recorded_on) }
        trend_dates = dated_snapshots.values.flatten.map(&:recorded_on).uniq.sort

        labels = trend_dates.map { |date| date.strftime("%b %-d") }
        values = trend_dates.map do |date|
          net_worth_accounts.sum do |account|
            latest_snapshot = dated_snapshots.fetch(account).select { |snapshot| snapshot.recorded_on <= date }.last
            latest_snapshot&.balance.to_f
          end.round(2)
        end

        [ labels, values ]
      end
    end

    def trend_rows
      @trend_rows ||= if target_reads?
        target_trend_rows
      else
        trend_labels.zip(trend_values).map do |label, value|
          { label: label, value: value, coverage_count: net_worth_accounts.size, account_count: net_worth_accounts.size, complete: true }
        end
      end
    end

    def target_trend_data
      [ target_trend_rows.map { |row| row.fetch(:label) }, target_trend_rows.map { |row| row[:value] } ]
    end

    def target_trend_rows
      @target_trend_rows ||= Accounts::TargetNetWorthTrend.call(accounts: net_worth_accounts)
    end

    def target_reads?
      accounts.any? && accounts.all? { |account| account.budget_workspace&.target_reads_enabled? }
    end
  end
end
