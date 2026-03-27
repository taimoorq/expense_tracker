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
        assets_total: assets_total,
        liabilities_total: liabilities_total,
        net_worth_total: assets_total - liabilities_total,
        latest_snapshot: latest_snapshot,
        accounts_with_snapshots_count: accounts_with_snapshots_count,
        accounts_missing_snapshots_count: accounts.size - accounts_with_snapshots_count,
        trend_labels: include_trend? ? trend_labels : [],
        trend_values: include_trend? ? trend_values : []
      }
    end

    private

    attr_reader :user

    def include_trend?
      @include_trend
    end

    def accounts
      @accounts ||= user.accounts.includes(:account_snapshots).active_first.to_a
    end

    def net_worth_accounts
      @net_worth_accounts ||= accounts.select(&:include_in_net_worth)
    end

    def assets_total
      @assets_total ||= net_worth_accounts.select(&:asset?).sum(&:display_balance)
    end

    def liabilities_total
      @liabilities_total ||= net_worth_accounts.select(&:liability?).sum { |account| account.display_balance.abs }
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

    def trend_labels
      trend_data.first
    end

    def trend_values
      trend_data.last
    end

    def trend_data
      @trend_data ||= begin
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
  end
end
