module BankConnections
  class Review
    def initialize(mapping:, balance:)
      @mapping, @balance = mapping, balance
    end

    def transactions
      return [] unless @mapping.account && @balance
      workspace = @mapping.budget_workspace
      day = @balance.reported_at.in_time_zone(workspace.time_zone).to_date
      @mapping.account.account_postings.joins(:financial_transaction).includes(:financial_transaction)
        .where(financial_transactions: { state: "posted" })
        .where("(account_postings.effective_at >= :start AND account_postings.effective_at < :finish) OR (account_postings.effective_at IS NULL AND financial_transactions.effective_on = :day)", start: Accounts::TransactionTiming.at(date: day, incoming: true, workspace: workspace), finish: Accounts::TransactionTiming.at(date: day.next_day, incoming: true, workspace: workspace), day: day)
        .map(&:financial_transaction).uniq
    end
  end
end
