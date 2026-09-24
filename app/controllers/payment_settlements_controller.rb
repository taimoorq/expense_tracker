class PaymentSettlementsController < ApplicationController
  def destroy
    context = Identity::PersonalWorkspaceProvisioner.call(user: current_user)
    settlement = PaymentSettlement.where(budget_workspace: context.workspace).find(params[:id])
    Accounts::UndoManualSettlement.call(settlement: settlement, membership: context.membership)
    redirect_to activity_path(view: "payments"), notice: "Clearing undone. The payment is reserved again.", status: :see_other
  rescue ArgumentError => error
    redirect_to activity_path(view: "payments"), alert: error.message, status: :see_other
  rescue Identity::WorkspaceAccess::NotAuthorized
    head :forbidden
  end

  def create
    context = Identity::PersonalWorkspaceProvisioner.call(user: current_user)
    commitment = context.workspace.payment_commitments.find(params.require(:payment_commitment_id))
    raise ArgumentError, "Confirm that the money has cleared your account." unless params[:confirmed] == "1"
    Accounts::SettlePaymentManually.call(commitment: commitment, membership: context.membership, cleared_on: Date.iso8601(params.require(:cleared_on)))
    redirect_back fallback_location: activity_path(view: "payments"), notice: "Payment cleared. Its reservation was replaced by recorded activity.", status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_back fallback_location: activity_path(view: "payments"), alert: error.message, status: :see_other
  rescue Identity::WorkspaceAccess::NotAuthorized
    head :forbidden
  end
end
