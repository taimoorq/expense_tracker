class PlanningTemplatesController < ApplicationController
  def index
    @pay_schedules = current_user.pay_schedules.order(:name)
    @pay_schedule = current_user.pay_schedules.new

    @subscriptions = current_user.subscriptions.order(:due_day, :name)
    @subscription = current_user.subscriptions.new

    @monthly_bills = current_user.monthly_bills.order(:kind, :due_day, :name)
    @monthly_bill = current_user.monthly_bills.new

    @payment_plans = current_user.payment_plans.order(:due_day, :name)
    @payment_plan = current_user.payment_plans.new

    @credit_cards = current_user.credit_cards.order(:priority, :name)
    @credit_card = current_user.credit_cards.new
  end
end
