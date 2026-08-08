module Accounts
  class TargetNetWorthTrend
    MAX_POINTS = 36

    def self.call(accounts:, as_of: Date.current)
      new(accounts: accounts, as_of: as_of).call
    end

    def initialize(accounts:, as_of:)
      @accounts = Array(accounts)
      @as_of = as_of.to_date
    end

    def call
      trend_dates.map do |date|
        balances = accounts.filter_map { |account| balance_on(account, date) }
        complete = balances.size == accounts.size
        {
          date: date,
          label: date.strftime("%b %-d"),
          value: complete ? balances.sum.round(2).to_f : nil,
          coverage_count: balances.size,
          account_count: accounts.size,
          complete: complete
        }
      end
    end

    private

    attr_reader :accounts, :as_of

    def account_ids
      @account_ids ||= accounts.map(&:id)
    end

    def observations_by_account
      @observations_by_account ||= BalanceObservation
        .where(account_id: account_ids, status: "trusted")
        .where(effective_through_at: ..as_of.end_of_day)
        .order(:effective_through_at, :created_at)
        .to_a
        .group_by(&:account_id)
    end

    def posting_totals
      @posting_totals ||= begin
        return {} if account_ids.empty?

        AccountPosting
          .joins(:financial_transaction)
          .where(account_id: account_ids, financial_transactions: { state: "posted", effective_on: ..as_of })
          .group(:account_id, "financial_transactions.effective_on")
          .sum(:amount)
      end
    end

    def trend_dates
      @trend_dates ||= (observations_by_account.values.flatten.map { |observation| observation.effective_through_at.to_date } + [ as_of ])
        .select { |date| date <= as_of }
        .uniq
        .sort
        .last(MAX_POINTS)
    end

    def balance_on(account, date)
      observation = observations_by_account.fetch(account.id, []).reverse.find do |candidate|
        candidate.effective_through_at.to_date <= date
      end
      return if observation.blank?

      delta = posting_totals.sum do |(account_id, effective_on), amount|
        next 0.to_d unless account_id == account.id
        next 0.to_d unless effective_on > observation.effective_through_at.to_date && effective_on <= date

        amount.to_d
      end
      observation.balance.to_d + delta
    end
  end
end
