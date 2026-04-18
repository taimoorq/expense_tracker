module Recurring
  class MonthGenerationRunner
    Result = Data.define(:budget_month, :message)

    ACTIONS = {
      paychecks: { generator: Recurring::GenerateMonthPaychecks, label: "paycheck" },
      subscriptions: { generator: Recurring::GenerateMonthSubscriptions, label: "subscription" },
      monthly_bills: { generator: Recurring::GenerateMonthMonthlyBills, label: "monthly bill" },
      payment_plans: { generator: Recurring::GenerateMonthPaymentPlans, label: "payment-plan" },
      credit_cards: { generator: Recurring::EstimateMonthCreditCards, label: "credit-card payment", verb: "Estimated" }
    }.freeze

    def self.call(user:, budget_month_id:, action:)
      new(user: user, budget_month_id: budget_month_id, action: action).call
    end

    def initialize(user:, budget_month_id:, action:)
      @user = user
      @budget_month_id = budget_month_id
      @action = action.to_sym
    end

    def call
      definition = ACTIONS.fetch(action)
      budget_month = user.budget_months.find(budget_month_id)
      created_count = definition.fetch(:generator).new(budget_month: budget_month).call
      verb = definition.fetch(:verb, "Generated")
      label = definition.fetch(:label)
      Result.new(budget_month: budget_month, message: "#{verb} #{created_count} #{label} entr#{created_count == 1 ? 'y' : 'ies'}.")
    end

    private

    attr_reader :user, :budget_month_id, :action
  end
end
