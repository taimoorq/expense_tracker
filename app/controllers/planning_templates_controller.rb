class PlanningTemplatesController < ApplicationController
  TEMPLATE_COLLECTIONS = {
    pay_schedules: {
      order: [ :name ],
      edit_param: :edit_pay_schedule_id,
      associations: :linked_account
    },
    subscriptions: {
      order: [ :due_day, :name ],
      edit_param: :edit_subscription_id,
      associations: :linked_account
    },
    monthly_bills: {
      order: [ :kind, :due_day, :name ],
      edit_param: :edit_monthly_bill_id,
      associations: :linked_account
    },
    payment_plans: {
      order: [ :due_day, :name ],
      edit_param: :edit_payment_plan_id,
      associations: :linked_account
    },
    credit_cards: {
      order: [ :priority, :name ],
      edit_param: :edit_credit_card_id,
      associations: [ :linked_account, :payment_account ]
    }
  }.freeze

  def index
    TEMPLATE_COLLECTIONS.each do |collection_name, config|
      assign_planning_template(collection_name, **config)
    end
  end

  private

  def assign_planning_template(collection_name, order:, edit_param:, associations:)
    scope = current_user.public_send(collection_name)

    instance_variable_set("@#{collection_name}", scope.includes(*Array(associations)).order(*order))
    instance_variable_set("@#{collection_name.to_s.singularize}", find_planning_template_record(scope, edit_param) || scope.new)
  end

  def find_planning_template_record(scope, param_key)
    scope.find_by(id: params[param_key]) if params[param_key].present?
  end
end
