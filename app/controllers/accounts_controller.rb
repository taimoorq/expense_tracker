class AccountsController < ApplicationController
  def index
    @accounts = current_user.accounts.includes(:account_snapshots).active_first
    @account = current_user.accounts.new
    @net_worth_accounts = @accounts.select(&:include_in_net_worth)
    @assets_total = @net_worth_accounts.select(&:asset?).sum(&:display_balance)
    @liabilities_total = @net_worth_accounts.select(&:liability?).sum { |account| account.display_balance.abs }
    @net_worth_total = @assets_total - @liabilities_total
    @latest_snapshot = current_user.account_snapshots.joins(:account).merge(Account.where(user: current_user)).order(recorded_on: :desc, created_at: :desc).first
    @accounts_with_snapshots_count = @accounts.count(&:latest_snapshot)
    @accounts_missing_snapshots_count = @accounts.count - @accounts_with_snapshots_count
    @trend_labels, @trend_values = net_worth_trend(@net_worth_accounts)
  end

  def show
    @account = current_user.accounts.includes(:account_snapshots).find(params[:id])
    @account_snapshot = AccountSnapshot.new(account: @account, recorded_on: Date.current)
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

  def net_worth_trend(accounts)
    dated_snapshots = accounts.index_with { |account| account.account_snapshots.sort_by(&:recorded_on) }
    trend_dates = dated_snapshots.values.flatten.map(&:recorded_on).uniq.sort

    labels = trend_dates.map { |date| date.strftime("%b %-d") }
    values = trend_dates.map do |date|
      accounts.sum do |account|
        latest_snapshot = dated_snapshots.fetch(account).select { |snapshot| snapshot.recorded_on <= date }.last
        latest_snapshot&.balance.to_f
      end.round(2)
    end

    [ labels, values ]
  end

  def account_params
    params.require(:account).permit(:name, :institution_name, :kind, :active, :include_in_net_worth, :include_in_cash, :notes)
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
