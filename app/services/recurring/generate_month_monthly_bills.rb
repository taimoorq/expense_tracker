module Recurring
  class GenerateMonthMonthlyBills
    def initialize(budget_month:, bills: budget_month.user.monthly_bills.active_only)
      @budget_month = budget_month
      @bills = bills
    end

    def call
      Recurring::GenerateMonthRecurringEntries.new(budget_month: @budget_month, templates: @bills).call
    end
  end
end
