class ProviderTransactionsController < ApplicationController
  def update
    context = Identity::PersonalWorkspaceProvisioner.call(user: current_user)
    workspace, membership = context.workspace, context.membership
    BankConnections::Access.authorize!(workspace: workspace, membership: membership)
    @source = workspace.provider_transactions.find(params[:id])
    if params[:choice] == "undo"
      BankConnections::UnacceptTransaction.call(source: @source, membership: membership)
    elsif params[:choice] == "existing"
      transaction = workspace.financial_transactions.find(params.require(:financial_transaction_id))
      BankConnections::AttachExistingTransaction.call(source: @source, transaction: transaction, membership: membership, digest: params.require(:digest))
    elsif params[:choice] == "restore"
      @source.with_lock do
        raise ArgumentError, "Undo accepted activity first." if @source.financial_transaction_id
        @source.update!(state: "review")
      end
    elsif params[:choice] == "ignore"
      @source.with_lock do
        raise ArgumentError, "Accepted activity must be corrected through reconciliation." if @source.financial_transaction_id
        @source.update!(state: "ignored")
      end
    else
      entry = current_user.expense_entries.find(params[:expense_entry_id]) if params[:expense_entry_id].present?
      transfer = workspace.accounts.find(params[:transfer_account_id]) if params[:transfer_account_id].present?
      counterpart = workspace.provider_transactions.find(params[:counterpart_id]) if params[:counterpart_id].present?
      BankConnections::AcceptTransaction.call(source: @source, membership: membership, digest: params.require(:digest), entry: entry,
        transfer_account: transfer, counterpart: counterpart)
    end
    redirect_to review_destination, notice: "Transaction review saved.", status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to review_destination, alert: error.message, status: :see_other
  rescue Identity::WorkspaceAccess::NotAuthorized
    head :forbidden
  end

  private

  def review_destination
    params[:return_to] == "activity" ? activity_path(view: params[:view].presence || "bank", account_id: params[:account_id].presence) : bank_connection_path(@source.connected_account.bank_connection)
  end
end
