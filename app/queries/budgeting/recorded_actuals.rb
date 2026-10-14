module Budgeting
  # Posting-period actuals are distinct from allocations to a planning period.
  # A cross-month match contributes here on its recorded date, and to the plan
  # summary in the month containing the matched item.
  class RecordedActuals
    def self.call(period:)
      for_periods(periods: [ period ]).fetch(period.id)
    end

    def self.for_periods(periods:)
      return {} if periods.empty?
      workspace = periods.first.budget_workspace
      raise ArgumentError, "Periods must share a workspace" unless periods.all? { |period| period.budget_workspace_id == workspace.id }
      transactions = workspace.financial_transactions.state_posted
        .where(effective_on: periods.map(&:starts_on).min..periods.map(&:starts_on).max.end_of_month)
      rows = transactions
        .left_joins(:budget_allocations)
        .group("financial_transactions.id")
        .pluck(
          "financial_transactions.id",
          "financial_transactions.flow_kind",
          "financial_transactions.gross_amount",
          "financial_transactions.effective_on",
          Arel.sql("COALESCE(SUM(budget_allocations.amount), 0)")
        ).group_by { |row| row[3].beginning_of_month }
      periods.to_h do |period|
        totals = { "income" => 0.to_d, "outflow" => 0.to_d, "transfer" => 0.to_d,
          "unallocated_income" => 0.to_d, "unallocated_outflow" => 0.to_d, "transaction_count" => 0 }
        rows.fetch(period.starts_on, []).each do |_id, flow, amount, _, allocated_amount|
          next unless totals.key?(flow)
          totals[flow] += amount
          totals["transaction_count"] += 1
          if flow.in?(%w[income outflow])
            totals["unallocated_#{flow}"] += [ amount - allocated_amount, 0 ].max
          end
        end
        [ period.id, totals.merge("net" => totals["income"] - totals["outflow"]) ]
      end
    end
  end
end
