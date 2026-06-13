module AccountSetup
  extend ActiveSupport::Concern

  private

  def default_account_attributes
    { include_in_net_worth: true }
  end

  def build_credit_card_payment_schedule_form(account)
    current_user.credit_cards.new(
      name: account.name,
      linked_account: account,
      due_day: 1,
      priority: 1,
      active: true
    )
  end

  def initial_snapshot_params
    account_scope = params.fetch(:account, ActionController::Parameters.new)
    snapshot_scope = account_scope[:initial_snapshot] || ActionController::Parameters.new

    if snapshot_scope.respond_to?(:permit)
      snapshot_scope.permit(:recorded_on, :balance, :available_balance, :notes)
    else
      ActionController::Parameters.new(snapshot_scope).permit(:recorded_on, :balance, :available_balance, :notes)
    end
  end

  def credit_card_payment_schedule_params
    account_scope = params.fetch(:account, ActionController::Parameters.new)
    schedule_scope = account_scope[:credit_card_payment_schedule] || ActionController::Parameters.new

    if schedule_scope.respond_to?(:permit)
      schedule_scope.permit(:enabled, :payment_account_id, :minimum_payment, :due_day, :priority, :active, :notes)
    else
      ActionController::Parameters.new(schedule_scope).permit(:enabled, :payment_account_id, :minimum_payment, :due_day, :priority, :active, :notes)
    end
  end
end
