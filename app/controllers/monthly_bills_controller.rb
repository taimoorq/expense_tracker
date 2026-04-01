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
    [ :name, :kind, :default_amount, :due_day, :linked_account_id, :account, :active, :notes, :billing_frequency, { billing_months: [] } ]
  end

  def resource_params
    params.require(:monthly_bill).permit(*permitted_attributes)
  end

  def create_success_message
    "Monthly bill saved."
  end

  def destroy_success_message
    "Monthly bill removed."
  end

  def update_success_message
    "Monthly bill updated."
  end
end
