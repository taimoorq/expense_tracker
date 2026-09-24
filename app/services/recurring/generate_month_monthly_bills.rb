module Recurring
  class GenerateMonthMonthlyBills
    def initialize(budget_month:, bills: budget_month.user.monthly_bills.active_only)
      @budget_month = budget_month
      @bills = bills
    end

    def call
      scheduled_bills = @bills.to_a.select { |bill| bill.scheduled_for_month?(@budget_month.month_on) }
      ActiveRecord::Associations::Preloader.new(records: scheduled_bills, associations: :linked_account).call if scheduled_bills.any?
      Recurring::GenerateMonthRecurringEntries.new(budget_month: @budget_month, templates: scheduled_bills).call
    end
  end
end
