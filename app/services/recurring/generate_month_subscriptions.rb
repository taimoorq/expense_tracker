module Recurring
  class GenerateMonthSubscriptions
    def initialize(budget_month:, subscriptions: budget_month.user.subscriptions.active_only)
      @budget_month = budget_month
      @subscriptions = subscriptions
    end

    def call
      Recurring::GenerateMonthRecurringEntries.new(budget_month: @budget_month, templates: @subscriptions).call
    end
  end
end
