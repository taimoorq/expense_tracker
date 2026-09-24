module Accounts
  class BankPosition
    attr_reader :account, :as_of, :horizon

    def initialize(account:, as_of: Date.current, horizon: nil, evidence: nil)
      @account, @as_of = account, as_of.to_date
      @horizon = horizon || @as_of.end_of_month
      @evidence = evidence || BankEvidence.new(accounts: [ account ], through_on: [ @as_of, @horizon ].max)
    end

    def observation
      return unless account.connected_account&.use_bank_balance?
      @observation ||= @evidence.observations(account).reverse.find do |observation|
        observation.effective_through_at <= TransactionTiming.at(date: as_of, incoming: false, workspace: account.budget_workspace)
      end
    end

    def policy
      @policy ||= BankBalancePolicy.new(account: account, observation: observation)
    end

    def postings
      @postings ||= @evidence.postings(account).select do |posting|
        date = posting.effective_at&.in_time_zone(account.budget_workspace.time_zone)&.to_date || posting.financial_transaction.effective_on
        date <= as_of
      end
    end

    def commitments
      @commitments ||= @evidence.commitments(account).select { |payment| payment.initiated_on <= as_of }
    end

    def unresolved?
      observation && (postings.any? { |posting| policy.disposition(posting) == "unknown" } || commitments.any? { |payment| policy.payment_disposition(payment) == "unknown" })
    end

    def result
      return unless observation
      outside = postings.select { |posting| policy.disposition(posting) == "outside" }
      reserved = commitments.select { |payment| policy.payment_disposition(payment) == "outside" }.sum(&:outstanding_amount)
      delta = outside.sum { |posting| posting.amount.to_d } - reserved
      plans = planned_items
      planned = plans.sum { |item, remaining| item_delta(item, remaining) }
      current = observation.balance + delta
      BalanceResolver::Result.new(account: account, snapshot: nil, balance_source: :bank_sync,
        balance_source_label: unresolved? ? "SimpleFIN · needs reconciliation" : "SimpleFIN · app estimate",
        balance_source_record: observation, balance_source_recorded_on: observation.effective_through_at.in_time_zone(account.budget_workspace.time_zone).to_date,
        activity_through_on: outside.map { |posting| posting.effective_at&.in_time_zone(account.budget_workspace.time_zone)&.to_date || posting.financial_transaction.effective_on }.max,
        base_balance: observation.balance, paid_delta: delta, planned_delta: planned, current_balance: current,
        projected_balance: current + planned, paid_entries_count: outside.size + commitments.size, planned_entries_count: plans.size,
        balance_available: !unresolved?)
    end

    def planned_items
      @evidence.plans(account).select { |item, _| item.scheduled_on <= horizon }
    end

    def item_delta(item, amount)
      delta = item.intended_source_account_id == account.id ? (item.flow_kind_income? ? amount : -amount) : 0.to_d
      delta += amount if item.intended_destination_account_id == account.id
      delta
    end
  end
end
