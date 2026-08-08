module Budgeting
  class CloseReadiness
    Result = Data.define(
      :period, :summary, :unmatched_count, :unresolved_account_count,
      :issue_count, :ready, :calculation_version
    ) do
      def ready?
        ready
      end
    end

    def self.call(period:)
      new(period: period).call
    end

    def initialize(period:)
      @period = period
    end

    def call
      summary = Budgeting::PeriodSummary.call(period: period)
      unresolved_count = unresolved_account_count
      issue_count = summary.unmatched_count + unresolved_count
      Result.new(
        period: period,
        summary: summary,
        unmatched_count: summary.unmatched_count,
        unresolved_account_count: unresolved_count,
        issue_count: issue_count,
        ready: issue_count.zero?,
        calculation_version: Budgeting::PeriodSummary::CALCULATION_VERSION
      )
    end

    private

    attr_reader :period

    def unresolved_account_count
      trusted_account_ids = period.budget_workspace.balance_observations
        .trusted
        .where(effective_through_at: ..period.starts_on.end_of_month.end_of_day)
        .select(:account_id)
      period.budget_workspace.accounts
        .where(archived_at: nil)
        .where.not(id: trusted_account_ids)
        .count
    end
  end
end
