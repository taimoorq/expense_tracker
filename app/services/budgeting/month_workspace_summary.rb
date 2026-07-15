module Budgeting
  class MonthWorkspaceSummary
    Result = Data.define(
      :income,
      :planned_outflow,
      :actual_outflow,
      :leftover,
      :review_count,
      :actual_coverage_count,
      :outflow_count
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
      Result.new(
        income: budget_month.income_total,
        planned_outflow: outflow_entries.sum { |entry| entry.planned_amount.to_d },
        actual_outflow: outflow_entries.sum { |entry| entry.actual_amount.to_d },
        leftover: budget_month.calculated_leftover,
        review_count: review_result.issue_count,
        actual_coverage_count: outflow_entries.count { |entry| entry.actual_amount.present? },
        outflow_count: outflow_entries.count
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
  end
end
