module Budgeting
  class LegacyPeriodSummary
    def self.call(budget_month:)
      new(budget_month: budget_month).call
    end

    def initialize(budget_month:)
      @budget_month = budget_month
    end

    def call
      planned = totals_by_flow { |entry| entry.planned_amount.to_d }
      actual = totals_by_flow { |entry| actual_amount(entry) }
      remaining = totals_by_flow { |entry| [ entry.planned_amount.to_d - actual_amount(entry), 0 ].max }

      Budgeting::PeriodSummary::Result.new(
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
        unmatched_count: unmatched_activity_count
      )
    end

    private

    attr_reader :budget_month

    def entries
      @entries ||= budget_month.expense_entries
        .where.not(status: ExpenseEntry.statuses.fetch("skipped"))
        .includes(:account_activities, source_account: :account_activity_imports, destination_account: :account_activity_imports)
        .to_a
    end

    def totals_by_flow
      totals = { "income" => 0.to_d, "outflow" => 0.to_d, "transfer" => 0.to_d }
      entries.each do |entry|
        totals[Platform::TargetTranslation::ExpenseEntry.flow_kind(entry)] += yield(entry)
      end
      totals
    end

    def actual_amount(entry)
      return 0.to_d unless entry.paid?
      return entry.account_activities.sum(&:amount).to_d if entry.account_activities.any?
      return 0.to_d if covered_by_import?(entry)

      entry.effective_amount.to_d
    end

    def covered_by_import?(entry)
      account = entry.source_account || entry.destination_account
      return false if account.blank? || entry.occurred_on.blank?

      account.account_activity_imports.any? do |activity_import|
        activity_import.started_on.present? && activity_import.ended_on.present? &&
          activity_import.started_on <= entry.occurred_on && activity_import.ended_on >= entry.occurred_on
      end
    end

    def unmatched_activity_count
      budget_month.user.account_activities
        .where(transaction_on: budget_month.month_on..budget_month.month_on.end_of_month)
        .where(expense_entry_id: nil)
        .count
    end
  end
end
