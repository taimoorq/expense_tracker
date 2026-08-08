module Budgeting
  class MonthWorkspaceSummary
    Result = Data.define(
      :income,
      :planned_outflow,
      :actual_outflow,
      :leftover,
      :review_count,
      :actual_coverage_count,
      :outflow_count,
      :calculation_version
    )

    def self.call(budget_month:, expense_entries: budget_month.expense_entries.to_a, today: Date.current)
      new(budget_month:, expense_entries:, today:).call
    end

    def initialize(budget_month:, expense_entries:, today:)
      @budget_month = budget_month
      @expense_entries = expense_entries.to_a
      @today = today
    end

    def call
      return target_result if target_period.present?

      Result.new(
        income: budget_month.income_total,
        planned_outflow: outflow_entries.sum { |entry| entry.planned_amount.to_d },
        actual_outflow: outflow_entries.sum { |entry| entry.actual_amount.to_d },
        leftover: budget_month.calculated_leftover,
        review_count: review_result.issue_count,
        actual_coverage_count: outflow_entries.count { |entry| entry.actual_amount.present? },
        outflow_count: outflow_entries.count,
        calculation_version: "legacy-compatible-v1"
      )
    end

    private

    attr_reader :budget_month, :expense_entries, :today

    def outflow_entries
      @outflow_entries ||= expense_entries.reject(&:income?)
    end

    def review_result
      @review_result ||= Budgeting::MonthReviewQuery.call(entries: expense_entries, reason: :all, today: today)
    end

    def target_result
      summary = Budgeting::PeriodSummary.call(period: target_period)
      target_outflow_items = target_period.budget_items
        .flow_kind_outflow
        .where.not(state: %w[skipped cancelled voided])
      covered_count = target_outflow_items
        .joins(budget_allocations: :financial_transaction)
        .where(financial_transactions: { state: "posted" })
        .distinct
        .count
      Result.new(
        income: summary.forecast_income,
        planned_outflow: summary.planned_outflow,
        actual_outflow: summary.actual_outflow,
        leftover: summary.forecast_net,
        review_count: target_review_summary.fetch(:review_attention_count),
        actual_coverage_count: covered_count,
        outflow_count: target_outflow_items.count,
        calculation_version: Budgeting::PeriodSummary::CALCULATION_VERSION
      )
    end

    def target_period
      return @target_period if defined?(@target_period)

      @target_period = begin
        workspace = BudgetWorkspace.find_by(legacy_owner_user_id: budget_month.user_id, target_reads_enabled: true)
        mapping = workspace&.legacy_record_mappings&.find_by(
          legacy_record_type: "BudgetMonth",
          legacy_record_id: budget_month.id,
          target_record_type: "BudgetPeriod"
        )
        workspace&.budget_periods&.find_by(id: mapping&.target_record_id)
      end
    end

    def target_review_summary
      @target_review_summary ||= Overview::TargetReviewSummary.call(period: target_period, today: today)
    end
  end
end
