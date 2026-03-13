class PlanningTemplatesController < ApplicationController
  def index
    @pay_schedules = PaySchedule.order(:name)
    @pay_schedule = PaySchedule.new

    @subscriptions = Subscription.order(:due_day, :name)
    @subscription = Subscription.new

    @monthly_bills = MonthlyBill.order(:kind, :due_day, :name)
    @monthly_bill = MonthlyBill.new

    @payment_plans = PaymentPlan.order(:due_day, :name)
    @payment_plan = PaymentPlan.new

    @credit_cards = CreditCard.order(:priority, :name)
    @credit_card = CreditCard.new
  end
end
