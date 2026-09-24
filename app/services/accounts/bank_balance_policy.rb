module Accounts
  # Source cutoffs and user-reviewed coverage are shared by account estimates
  # and running balances. Default ordering times cannot establish inclusion.
  class BankBalancePolicy
    def initialize(account:, observation:)
      @account, @observation = account, observation
      @day = observation.effective_through_at.in_time_zone(account.budget_workspace.time_zone).to_date
    end

    def disposition(posting)
      transaction = posting.financial_transaction
      explicit = @observation.transaction_coverage[transaction.id]
      return explicit if explicit
      instant = posting.effective_at || transaction.posted_at || transaction.transacted_at
      return instant > @observation.effective_through_at ? "outside" : "included" if instant
      return "included" if transaction.effective_on < @day
      return "outside" if transaction.effective_on > @day
      "unknown"
    end

    def payment_disposition(commitment)
      included = commitment.included_provider_balance
      return "included" if included && included.reported_at <= @observation.effective_through_at
      return "outside" if commitment.excluded_provider_balance_id == @observation.provider_balance_id
      return "outside" if commitment.reserved_at && commitment.reserved_at > @observation.observed_at
      "unknown"
    end
  end
end
