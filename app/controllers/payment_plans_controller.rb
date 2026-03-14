class PaymentPlansController < ApplicationController
  include PlanningTemplateCrud

  private

  def resource_name
    "payment_plan"
  end

  def resource_order
    [ :due_day, :name ]
  end

  def permitted_attributes
    [ :name, :total_due, :amount_paid, :monthly_target, :due_day, :account, :active, :notes ]
  end

  def create_success_message
    "Payment plan saved."
  end

  def destroy_success_message
    "Payment plan removed."
  end

  def update_success_message
    "Payment plan updated."
  end
end
