class CreditCardsController < ApplicationController
  include PlanningTemplateCrud

  private

  def resource_name
    "credit_card"
  end

  def resource_order
    [ :priority, :name ]
  end

  def permitted_attributes
    [ :name, :minimum_payment, :priority, :account, :active, :notes ]
  end

  def create_success_message
    "Credit card saved."
  end

  def destroy_success_message
    "Credit card removed."
  end

  def update_success_message
    "Credit card updated."
  end
end
