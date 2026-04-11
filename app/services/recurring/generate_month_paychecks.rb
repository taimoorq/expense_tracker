module Recurring
  class GenerateMonthPaychecks
    def initialize(budget_month:, schedules: budget_month.user.pay_schedules.active_only)
      @budget_month = budget_month
      @schedules = schedules
    end

    def call
      Recurring::GenerateMonthRecurringEntries.new(budget_month: @budget_month, templates: @schedules).call
    end
  end
end
