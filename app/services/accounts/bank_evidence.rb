module Accounts
  # One read bundle can serve all dates/accounts in a chart or summary. Avoid
  # rereading a complete ledger for every point in a bank-balance history.
  class BankEvidence
    def initialize(accounts:, through_on:)
      @accounts, @through_on = Array(accounts), through_on
    end

    def observations(account)
      @observations ||= BalanceObservation.trusted.where(account_id: ids, source_kind: "bank_sync")
        .where(effective_through_at: ..TransactionTiming.at(date: @through_on, incoming: false, workspace: workspace))
        .order(:effective_through_at, :created_at).group_by(&:account_id)
      @observations.fetch(account.id, [])
    end

    def postings(account)
      @postings ||= AccountPosting.where(account_id: ids).joins(:financial_transaction).includes(:financial_transaction)
        .where(financial_transactions: { state: "posted" })
        .where("financial_transactions.effective_on <= :date OR account_postings.effective_at <= :instant", date: @through_on, instant: TransactionTiming.at(date: @through_on, incoming: false, workspace: workspace)).group_by(&:account_id)
      @postings.fetch(account.id, [])
    end

    def commitments(account)
      @commitments ||= PaymentCommitment.where(account_id: ids, state: "reserved", initiated_on: ..@through_on)
        .includes(:included_provider_balance, :payment_settlements).group_by(&:account_id)
      @commitments.fetch(account.id, [])
    end

    def plans(account)
      @plans ||= begin
        items = workspace.budget_items.where(state: "open", scheduled_on: ..@through_on.end_of_month)
          .where("intended_source_account_id IN (:ids) OR intended_destination_account_id IN (:ids)", ids: ids).to_a
        remaining = PlannedRemainders.call(workspace: workspace, items: items)
        items.filter_map { |item| [ item, remaining.fetch(item.id) ] if remaining.fetch(item.id).positive? }
      end
      @plans.select { |item, _| [ item.intended_source_account_id, item.intended_destination_account_id ].include?(account.id) }
    end

    private

    def ids
      @ids ||= @accounts.map(&:id)
    end

    def workspace
      @accounts.first.budget_workspace
    end
  end
end
