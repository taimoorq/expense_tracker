module Budgeting
  class PeriodSummaryBatch
    def self.call(periods:)
      new(periods: periods).call
    end

    def initialize(periods:)
      @periods = Array(periods)
    end

    def call
      return {} if periods.empty?

      periods.index_with do |period|
        PeriodSummary.build_result(
          planned: planned.fetch(period.id, {}),
          actual: actual.fetch(period.id, {}),
          remaining: remaining.fetch(period.id, {}),
          unmatched_count: unmatched.fetch(period.starts_on, 0)
        )
      end
    end

    private

    attr_reader :periods

    def workspace
      @workspace ||= begin
        workspace = periods.first.budget_workspace
        unless periods.all? { |period| period.budget_workspace_id == workspace.id }
          raise ArgumentError, "periods must belong to one workspace"
        end
        workspace
      end
    end

    def period_ids
      @period_ids ||= periods.map(&:id)
    end

    def active_items
      workspace.budget_items.where(budget_period_id: period_ids).where.not(state: %w[skipped cancelled voided])
    end

    def planned
      @planned ||= nest_by_period(
        active_items.group(:budget_period_id, :flow_kind).sum(:planned_amount)
      )
    end

    def actual
      @actual ||= nest_by_period(
        workspace.budget_allocations
          .joins(:budget_item, :financial_transaction)
          .where(budget_items: { budget_period_id: period_ids })
          .where.not(budget_items: { state: %w[skipped cancelled voided] })
          .where(financial_transactions: { state: "posted" })
          .group("budget_items.budget_period_id", "budget_items.flow_kind")
          .sum("budget_allocations.amount")
      )
    end

    def remaining
      @remaining ||= begin
        allocation_totals = workspace.budget_allocations
          .joins(:financial_transaction)
          .where(financial_transactions: { state: "posted" })
          .group(:budget_item_id)
          .select(:budget_item_id, "SUM(budget_allocations.amount) AS allocated_amount")
        values = active_items
          .joins("LEFT JOIN (#{allocation_totals.to_sql}) allocation_totals ON allocation_totals.budget_item_id = budget_items.id")
          .group(:budget_period_id, :flow_kind)
          .sum("GREATEST(budget_items.planned_amount - COALESCE(allocation_totals.allocated_amount, 0), 0)")
        nest_by_period(values)
      end
    end

    def unmatched
      @unmatched ||= begin
        counts = workspace.financial_transactions
          .where(state: "posted", effective_on: periods.map(&:starts_on).min..periods.map(&:starts_on).max.end_of_month)
          .where.missing(:budget_allocations)
          .group("DATE_TRUNC('month', financial_transactions.effective_on)")
          .count
        counts.to_h { |month, count| [ month.to_date, count ] }
      end
    end

    def nest_by_period(values)
      values.each_with_object(Hash.new { |hash, period_id| hash[period_id] = {} }) do |((period_id, flow_kind), amount), grouped|
        grouped[period_id][flow_kind] = amount
      end
    end
  end
end
