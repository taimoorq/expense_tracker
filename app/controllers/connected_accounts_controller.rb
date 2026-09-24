class ConnectedAccountsController < ApplicationController
  before_action :load_mapping

  def reconcile
    @balance = @mapping.latest_balance
    @commitments = @mapping.account&.payment_commitments&.where(state: "reserved")&.includes(:expense_entry, :payment_settlements) || []
    @transactions = BankConnections::Review.new(mapping: @mapping, balance: @balance).transactions
  end

  def accept_balance
    BankConnections::AcceptBalance.call(mapping: @mapping, membership: @membership, balance_id: params.require(:balance_id),
      mapping_version: params.require(:mapping_version), dispositions: params.fetch(:payments, ActionController::Parameters.new).to_unsafe_h,
      coverage: params.fetch(:coverage, ActionController::Parameters.new).to_unsafe_h, confirmed: params[:confirmed] == "1")
    redirect_to account_path(@mapping.account), notice: "Bank balance accepted. Recorded payments and bank activity are counted once.", status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to reconcile_connected_account_path(@mapping), alert: error.message, status: :see_other
  end

  def manual_source
    @mapping.update!(use_bank_balance: false)
    redirect_to account_path(@mapping.account), notice: "Using your manual balance source. Bank balances remain visible.", status: :see_other
  end

  private

  def load_mapping
    context = Identity::PersonalWorkspaceProvisioner.call(user: current_user)
    @workspace, @membership = context.workspace, context.membership
    BankConnections::Access.authorize!(workspace: @workspace, membership: @membership)
    @mapping = @workspace.connected_accounts.find(params[:id])
    raise ActiveRecord::RecordNotFound unless @mapping.account
  rescue Identity::WorkspaceAccess::NotAuthorized
    head :forbidden
  end
end
