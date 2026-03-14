class PlanningTemplatesController < ApplicationController
  def index
    @pay_schedules = current_user.pay_schedules.order(:name)
    @pay_schedule = find_planning_template_record(current_user.pay_schedules, :edit_pay_schedule_id) || current_user.pay_schedules.new

    @subscriptions = current_user.subscriptions.order(:due_day, :name)
    @subscription = find_planning_template_record(current_user.subscriptions, :edit_subscription_id) || current_user.subscriptions.new

    @monthly_bills = current_user.monthly_bills.order(:kind, :due_day, :name)
    @monthly_bill = find_planning_template_record(current_user.monthly_bills, :edit_monthly_bill_id) || current_user.monthly_bills.new

    @payment_plans = current_user.payment_plans.order(:due_day, :name)
    @payment_plan = find_planning_template_record(current_user.payment_plans, :edit_payment_plan_id) || current_user.payment_plans.new

    @credit_cards = current_user.credit_cards.order(:priority, :name)
    @credit_card = find_planning_template_record(current_user.credit_cards, :edit_credit_card_id) || current_user.credit_cards.new
  end

  private

  def find_planning_template_record(scope, param_key)
    scope.find_by(id: params[param_key]) if params[param_key].present?
  end
end
