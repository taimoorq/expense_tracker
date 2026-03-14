class MonthlyBillsController < ApplicationController
  include PlanningTemplateCrud

  private

  def resource_name
    "monthly_bill"
  end

  def resource_order
    [ :kind, :due_day, :name ]
  end

  def permitted_attributes
    [ :name, :kind, :default_amount, :due_day, :account, :active, :notes ]
  end

  def create_success_message
    "Monthly bill template saved."
  end

  def destroy_success_message
    "Monthly bill template removed."
  end
end
