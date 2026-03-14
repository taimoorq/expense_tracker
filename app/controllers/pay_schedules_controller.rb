class PaySchedulesController < ApplicationController
  include PlanningTemplateCrud

  private

  def resource_name
    "pay_schedule"
  end

  def resource_order
    [ :name ]
  end

  def permitted_attributes
    [
      :name,
      :cadence,
      :amount,
      :first_pay_on,
      :day_of_month_one,
      :day_of_month_two,
      :weekend_adjustment,
      :account,
      :active
    ]
  end

  def create_success_message
    "Pay schedule saved."
  end

  def destroy_success_message
    "Pay schedule removed."
  end
end
