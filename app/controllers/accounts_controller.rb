class AccountsController < ApplicationController
  def index
    summary = Accounts::Summary.new(user: current_user, include_trend: true).call
    @accounts = summary.fetch(:accounts)
    @account = current_user.accounts.new
    @net_worth_accounts = summary.fetch(:net_worth_accounts)
    @assets_total = summary.fetch(:assets_total)
    @liabilities_total = summary.fetch(:liabilities_total)
    @net_worth_total = summary.fetch(:net_worth_total)
    @latest_snapshot = summary.fetch(:latest_snapshot)
    @accounts_with_snapshots_count = summary.fetch(:accounts_with_snapshots_count)
    @accounts_missing_snapshots_count = summary.fetch(:accounts_missing_snapshots_count)
    @trend_labels = summary.fetch(:trend_labels)
    @trend_values = summary.fetch(:trend_values)
  end

  def show
    @account = current_user.accounts.includes(:account_snapshots).find(params[:id])
    @account_snapshot = AccountSnapshot.new(account: @account, recorded_on: Date.current)
    @linked_entries = current_user.expense_entries
                                   .where(source_account_id: @account.id)
                                   .includes(:budget_month, :source_template)
                                   .order(occurred_on: :desc, created_at: :desc)
                                   .limit(150)
    @linked_entries_net = @linked_entries.sum(&:cashflow_amount)
    @connected_templates = {
      "Pay Schedules" => current_user.pay_schedules.where(linked_account_id: @account.id).order(active: :desc, name: :asc).to_a,
      "Subscriptions" => current_user.subscriptions.where(linked_account_id: @account.id).order(active: :desc, due_day: :asc, name: :asc).to_a,
      "Monthly Bills" => current_user.monthly_bills.where(linked_account_id: @account.id).order(active: :desc, due_day: :asc, name: :asc).to_a,
      "Payment Plans" => current_user.payment_plans.where(linked_account_id: @account.id).order(active: :desc, due_day: :asc, name: :asc).to_a,
      "Credit Cards" => current_user.credit_cards.where(linked_account_id: @account.id).order(active: :desc, priority: :asc, name: :asc).to_a,
      "Credit Card Payments" => current_user.credit_cards.where(payment_account_id: @account.id).order(active: :desc, priority: :asc, name: :asc).to_a
    }
    @connected_templates_count = @connected_templates.values.sum(&:size)
  end

  def sync_teller_snapshot
    account = current_user.accounts.find(params[:id])
    result = TellerAccountSnapshotSync.new(account: account).call

    if result.success?
      redirect_to account_path(account), notice: "Balance snapshot synced from Teller."
    else
      redirect_to account_path(account), alert: result.error
    end
  end

  def new
    @account = current_user.accounts.new(default_account_attributes)
    @initial_snapshot = @account.account_snapshots.new(recorded_on: Date.current)
  end

  def create
    @account = current_user.accounts.new(account_params)
    @initial_snapshot = build_initial_snapshot(@account)

    account_valid = @account.valid?
    snapshot_valid = @initial_snapshot.nil? || @initial_snapshot.valid?

    if account_valid && snapshot_valid
      Account.transaction do
        @account.save!
        @initial_snapshot&.save!
      end

      notice = @initial_snapshot.present? ? "Account created and initial balance recorded." : "Account created. Add a balance snapshot to start tracking it."
      redirect_to @account, notice: notice
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @account = current_user.accounts.find(params[:id])
  end

  def update
    @account = current_user.accounts.find(params[:id])

    if @account.update(account_params)
      redirect_to @account, notice: "Account updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def account_params
    params.require(:account).permit(
      :name,
      :institution_name,
      :kind,
      :active,
      :include_in_net_worth,
      :include_in_cash,
      :notes,
      :teller_sync_enabled,
      :teller_account_id,
      :teller_enrollment_id,
      :teller_access_token
    )
  end

  def default_account_attributes
    { include_in_net_worth: true }
  end

  def build_initial_snapshot(account)
    return nil unless initial_snapshot_requested?

    account.account_snapshots.new(initial_snapshot_params)
  end

  def initial_snapshot_requested?
    snapshot_params = initial_snapshot_params.to_h

    snapshot_params["balance"].present? || snapshot_params["available_balance"].present? || snapshot_params["notes"].present?
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
end
