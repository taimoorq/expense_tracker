class ActivityMatchesController < ApplicationController
  before_action :load_target_context

  def create
    transaction = @workspace.financial_transactions.find(params[:financial_transaction_id])
    budget_item = @workspace.budget_items.find(params[:budget_item_id])
    amount = params[:amount].presence || transaction.available_to_allocate
    Accounts::LegacyMatchBridge.match(
      workspace: @workspace,
      actor_membership: @membership,
      transaction: transaction,
      budget_item: budget_item,
      amount: amount,
      idempotency_key: "ui:match:#{transaction.id}:#{budget_item.id}:#{amount}"
    )
    redirect_to activity_path(view: "review"), notice: "Transaction matched to the plan."
  rescue Accounts::MatchTransaction::InvalidMatch,
    Accounts::LegacyMatchBridge::MissingLegacyPair,
    Accounts::LegacyMatchBridge::ConflictingLegacyMatch => error
    redirect_to activity_path(view: "review"), alert: error.message
  end

  def destroy
    allocation = @workspace.budget_allocations.find(params[:id])
    Accounts::LegacyMatchBridge.unmatch(
      workspace: @workspace,
      actor_membership: @membership,
      allocation: allocation,
      idempotency_key: "ui:unmatch:#{allocation.id}"
    )
    redirect_to activity_path(view: "all"), notice: "Transaction returned to review."
  rescue Accounts::UnmatchTransaction::InvalidMatch,
    Accounts::LegacyMatchBridge::MissingLegacyPair => error
    redirect_to activity_path(view: "all"), alert: error.message
  end

  private

  def load_target_context
    @workspace = BudgetWorkspace.find_by(legacy_owner_user_id: current_user.id, target_reads_enabled: true)
    raise ActiveRecord::RecordNotFound if @workspace.blank?

    @membership = @workspace.workspace_memberships.status_active.find_by!(user: current_user)
  end
end
