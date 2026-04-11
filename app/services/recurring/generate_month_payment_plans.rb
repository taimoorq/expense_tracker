module Recurring
  class GenerateMonthPaymentPlans
    def initialize(budget_month:, plans: budget_month.user.payment_plans.active_only)
      @budget_month = budget_month
      @plans = plans
    end

    def call
      Recurring::GenerateMonthRecurringEntries.new(budget_month: @budget_month, templates: @plans).call
    end
  end
end
