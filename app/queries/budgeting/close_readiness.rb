module Budgeting
  class CloseReadiness
    Result = Data.define(
      :period, :summary, :unmatched_count, :unresolved_account_count,
      :issue_count, :ready, :calculation_version, :reserved_count, :correction_count,
      :reconciliation_count, :pending_count, :bank_review_count, :blocking_count
    ) do
      def can_close?
        blocking_count.zero?
      end

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
      workspace = period.budget_workspace
      range = period.starts_on..period.starts_on.end_of_month
      reserved = workspace.payment_commitments.where(state: "reserved", initiated_on: ..range.end).count
      sources = workspace.provider_transactions.joins(:connected_account).where(connected_accounts: { state: "mapped" })
      current_sources = sources.where("COALESCE(provider_transactions.posted_at, provider_transactions.transacted_at) >= ? AND COALESCE(provider_transactions.posted_at, provider_transactions.transacted_at) < ?", range.begin.in_time_zone(workspace.time_zone), range.end.next_day.in_time_zone(workspace.time_zone))
      corrections = sources.where(state: "changed").joins(:financial_transaction).where("financial_transactions.effective_on BETWEEN ? AND ? OR provider_transactions.posted_at BETWEEN ? AND ?", range.begin, range.end, range.begin.in_time_zone(workspace.time_zone), range.end.end_of_day).count
      pending = current_sources.where(pending: true, state: %w[review changed]).count
      bank_review = current_sources.where(pending: false, state: "review").count
      accounts = workspace.accounts.where(archived_at: nil).includes(:connected_account).to_a
      accounts.each { |account| account.association(:budget_workspace).target = workspace }
      evidence = Accounts::BankEvidence.new(accounts: accounts, through_on: range.end)
      reconciliation = accounts.count { |account| Accounts::BankPosition.new(account: account, as_of: range.end, evidence: evidence).unresolved? }
      blocking = reserved + corrections + reconciliation
      unreviewed = workspace.financial_transactions.state_posted.where(effective_on: range, origin_kind: "institution_import", reviewed_at: nil).where.missing(:budget_allocations).count
      issue_count = unreviewed + unresolved_count + pending + bank_review + blocking
      Result.new(
        period: period,
        summary: summary,
        unmatched_count: summary.unmatched_count,
        unresolved_account_count: unresolved_count,
        issue_count: issue_count, reserved_count: reserved, correction_count: corrections,
        reconciliation_count: reconciliation, pending_count: pending, bank_review_count: bank_review, blocking_count: blocking,
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
