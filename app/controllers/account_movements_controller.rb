class AccountMovementsController < ApplicationController
  def show
    @budget_month = current_user.budget_months.find(params[:budget_month_id])
    @account = current_user.accounts.find(params[:account_id])
    @movement = Accounts::MovementDrilldown.new(
      budget_month: @budget_month,
      account: @account,
      movement_type: params[:movement_type]
    ).call
  rescue KeyError
    redirect_to root_path, alert: "Choose a valid account movement to review."
  end
end
