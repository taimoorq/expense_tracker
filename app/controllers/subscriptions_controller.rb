class SubscriptionsController < ApplicationController
  include PlanningTemplateCrud

  private

  def resource_name
    "subscription"
  end

  def resource_order
    [ :due_day, :name ]
  end

  def permitted_attributes
    [ :name, :amount, :due_day, :account, :active, :notes ]
  end

  def create_success_message
    "Subscription saved."
  end

  def destroy_success_message
    "Subscription removed."
  end

  def update_success_message
    "Subscription updated."
  end
end
