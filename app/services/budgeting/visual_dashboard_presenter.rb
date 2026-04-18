module Budgeting
  class VisualDashboardPresenter
    def initialize(budget_month:, expense_entries:)
      @budget_month = budget_month
      @entries = Array(expense_entries)
    end

    attr_reader :budget_month, :entries

    def sankey_payload
      @sankey_payload ||= Budgeting::MonthCashflowSankey.cached_payload(budget_month: budget_month, expense_entries: entries)
    end

    def account_flow_payload
      @account_flow_payload ||= Budgeting::MonthAccountFlowSummary.cached_payload(budget_month: budget_month, expense_entries: entries)
    end

    def section_totals
      @section_totals ||= outflow_entries
        .group_by(&:section)
        .transform_values { |items| items.sum { |item| item.effective_amount.to_f } }
        .sort_by { |_key, value| -value }
    end

    def section_labels
      section_totals.map { |key, _value| key.humanize }
    end

    def section_values
      section_totals.map { |_key, value| value.round(2) }
    end

    def line_labels
      running_balance_points[:labels]
    end

    def line_values
      running_balance_points[:values]
    end

    def cumulative_outflow_labels
      cumulative_outflow_points[:labels]
    end

    def cumulative_outflow_values
      cumulative_outflow_points[:values]
    end

    def over_budget_labels
      over_budget_categories.map(&:first)
    end

    def over_budget_values
      over_budget_categories.map(&:last)
    end

    def income
      budget_month.income_total.to_f
    end

    def leftover
      budget_month.calculated_leftover.to_f
    end

    def savings_pct
      income.positive? ? ((leftover / income) * 100).round(1) : 0
    end

    def top_category
      section_totals.first
    end

    private

    def outflow_entries
      @outflow_entries ||= entries.reject(&:income?)
    end

    def ordered_entries
      @ordered_entries ||= entries.sort_by { |entry| [ entry.occurred_on || Date.new(9999, 12, 31), entry.created_at ] }
    end

    def running_balance_points
      @running_balance_points ||= ordered_entries.each_with_object({ labels: [], values: [], running: 0.0 }) do |entry, memo|
        memo[:running] += entry.cashflow_amount.to_f
        memo[:labels] << (entry.occurred_on&.strftime("%b %-d") || "No Date")
        memo[:values] << memo[:running].round(2)
      end.slice(:labels, :values)
    end

    def cumulative_outflow_points
      @cumulative_outflow_points ||= begin
        spending_entries = outflow_entries.select { |entry| entry.occurred_on.present? }
        spending_entries.sort_by { |entry| [ entry.occurred_on, entry.created_at ] }.each_with_object({ labels: [], values: [], running: 0.0 }) do |entry, memo|
          memo[:running] += entry.effective_amount.to_f
          memo[:labels] << entry.occurred_on.strftime("%b %-d")
          memo[:values] << memo[:running].round(2)
        end.slice(:labels, :values)
      end
    end

    def over_budget_categories
      @over_budget_categories ||= outflow_entries
        .group_by { |entry| entry.category.presence || "Uncategorized" }
        .map do |category, items|
          planned_total = items.sum { |item| item.planned_amount.to_f }
          actual_total = items.sum { |item| item.actual_amount.to_f }
          [ category, planned_total.round(2), actual_total.round(2), (actual_total - planned_total).round(2) ]
        end
        .select { |_category, _planned, _actual, variance| variance.positive? }
        .sort_by { |_category, _planned, _actual, variance| -variance }
        .first(8)
    end
  end
end
