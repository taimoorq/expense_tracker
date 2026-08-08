module Budgeting
  class PeriodSummary
    CALCULATION_VERSION = "target-v1".freeze
    Result = Data.define(
      :planned_income,
      :planned_outflow,
      :planned_net,
      :actual_income,
      :actual_outflow,
      :actual_net,
      :remaining_income,
      :remaining_outflow,
      :forecast_income,
      :forecast_outflow,
      :forecast_net,
      :income_variance,
      :outflow_variance,
      :unmatched_count
    )

    def self.call(period:)
      new(period: period).call
    end

    def self.build_result(planned:, actual:, remaining:, unmatched_count:)
      planned = normalize_amounts(planned)
      actual = normalize_amounts(actual)
      remaining = normalize_amounts(remaining)

      Result.new(
        planned_income: planned["income"],
        planned_outflow: planned["outflow"],
        planned_net: planned["income"] - planned["outflow"],
        actual_income: actual["income"],
        actual_outflow: actual["outflow"],
        actual_net: actual["income"] - actual["outflow"],
        remaining_income: remaining["income"],
        remaining_outflow: remaining["outflow"],
        forecast_income: actual["income"] + remaining["income"],
        forecast_outflow: actual["outflow"] + remaining["outflow"],
        forecast_net: actual["income"] + remaining["income"] - actual["outflow"] - remaining["outflow"],
        income_variance: actual["income"] - planned["income"],
        outflow_variance: actual["outflow"] - planned["outflow"],
        unmatched_count: unmatched_count
      )
    end

    def self.normalize_amounts(values)
      {
        "income" => values.fetch("income", 0).to_d,
        "outflow" => values.fetch("outflow", 0).to_d,
        "transfer" => values.fetch("transfer", 0).to_d
      }
    end
    private_class_method :normalize_amounts

    def initialize(period:)
      @period = period
    end

    def call
      self.class.build_result(
        planned: active_items.group(:flow_kind).sum(:planned_amount),
        actual: actual_scope.group("budget_items.flow_kind").sum("budget_allocations.amount"),
        remaining: remaining_by_flow,
        unmatched_count: unmatched_transactions.count
      )
    end

    private

    attr_reader :period

    def active_items
      period.budget_items.where.not(state: %w[skipped cancelled voided])
    end

    def actual_scope
      BudgetAllocation
        .joins(:budget_item, :financial_transaction)
        .where(budget_items: { budget_period_id: period.id })
        .where.not(budget_items: { state: %w[skipped cancelled voided] })
        .where(financial_transactions: { state: "posted" })
    end

    def remaining_by_flow
      allocation_totals = BudgetAllocation
        .joins(:financial_transaction)
        .where(financial_transactions: { state: "posted" })
        .group(:budget_item_id)
        .select(:budget_item_id, "SUM(budget_allocations.amount) AS allocated_amount")

      active_items
        .joins("LEFT JOIN (#{allocation_totals.to_sql}) allocation_totals ON allocation_totals.budget_item_id = budget_items.id")
        .group(:flow_kind)
        .sum("GREATEST(budget_items.planned_amount - COALESCE(allocation_totals.allocated_amount, 0), 0)")
    end

    def unmatched_transactions
      period.budget_workspace.financial_transactions
        .where(state: "posted", effective_on: period.starts_on..period.starts_on.end_of_month)
        .where.missing(:budget_allocations)
    end
  end
end
