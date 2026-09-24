class ActivityTransactionsController < ApplicationController
  before_action :load_workspace

  def new
    @values = { effective_on: Date.current, flow_kind: "outflow", account_id: params[:account_id], idempotency_key: SecureRandom.uuid }
  end

  def create
    @values = params.expect(transaction: %i[effective_on transaction_time description amount flow_kind account_id destination_account_id memo idempotency_key]).to_h.symbolize_keys
    account = @accounts.find(@values.fetch(:account_id))
    values = @values.slice(:effective_on, :transaction_time, :description, :amount, :flow_kind, :memo)
    values[:effective_on] = Date.iso8601(values.fetch(:effective_on))
    if values[:flow_kind] == "transfer"
      values.merge!(source_account: account, destination_account: @accounts.find(@values.fetch(:destination_account_id)))
    else
      values[:account] = account
    end
    Accounts::RecordManualTransaction.call(workspace: @workspace, actor_membership: @membership,
      idempotency_key: "ui:manual:#{@values.fetch(:idempotency_key)}", attributes: values)
    redirect_to activity_path(view: "all", account_id: account.id), notice: "Transaction recorded. You can match it to a plan or leave it unplanned.", status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid, KeyError, Platform::Operations::Executor::IdempotencyConflict => error
    @error = error.message
    render :new, status: :unprocessable_content
  end

  def update
    transaction = @workspace.financial_transactions.find(params[:id])
    @workspace.with_lock do
      Accounts::OpenPeriodGuard.call(workspace: @workspace, dates: [ transaction.effective_on ])
      raise ArgumentError, "Only posted activity can be reviewed." unless transaction.state_posted?
      transaction.update!(reviewed_at: params[:choice] == "unreview" ? nil : Time.current)
      Audit::Recorder.call(workspace: @workspace, actor_membership: @membership, operation_run: nil,
        entity: transaction, action: "edit", changed_fields: %i[reviewed_at])
    end
    redirect_back fallback_location: activity_path, notice: "Activity review saved.", status: :see_other
  rescue ArgumentError => error
    redirect_back fallback_location: activity_path, alert: error.message, status: :see_other
  end

  def destroy
    transaction = @workspace.financial_transactions.find(params[:id])
    @workspace.with_lock do
      Accounts::OpenPeriodGuard.call(workspace: @workspace, dates: [ transaction.effective_on ])
      unless transaction.origin_kind_manual? && transaction.idempotency_key.to_s.start_with?("operation:") &&
          transaction.provider_transactions.empty? && transaction.budget_allocations.empty? && transaction.payment_settlements.empty?
        raise ArgumentError, "Unmatch this activity first. Bank activity and cleared payments must be corrected through their original review."
      end
      transaction.update!(state: "reversed")
      Audit::Recorder.call(workspace: @workspace, actor_membership: @membership, operation_run: nil,
        entity: transaction, action: "reverse", changed_fields: %i[state])
    end
    redirect_to activity_path(view: "all"), notice: "Manual transaction reversed. Record a replacement if needed.", status: :see_other
  rescue ArgumentError => error
    redirect_back fallback_location: activity_path, alert: error.message, status: :see_other
  end

  private

  def load_workspace
    @workspace = BudgetWorkspace.find_by!(legacy_owner_user: current_user, target_reads_enabled: true, target_writes_enabled: true)
    @membership = @workspace.workspace_memberships.status_active.find_by!(user: current_user)
    Identity::WorkspaceAccess.authorize_write!(workspace: @workspace, membership: @membership)
    @accounts = @workspace.accounts.where(user: current_user).order(:name)
  rescue Identity::WorkspaceAccess::NotAuthorized
    head :forbidden
  end
end
