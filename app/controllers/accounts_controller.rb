class AccountsController < ApplicationController
  include AccountSetup

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
    detail_page = Accounts::DetailPage.new(account: @account).call
    @balance_summary = detail_page.fetch(:balance_summary)
    @balance_history_rows = detail_page.fetch(:balance_history_rows)
    @credit_card_progress = detail_page.fetch(:credit_card_progress)
    @linked_entries = detail_page.fetch(:linked_entries)
    @linked_entries_net = detail_page.fetch(:linked_entries_net)
    @connected_templates = detail_page.fetch(:connected_templates)
    @connected_templates_count = detail_page.fetch(:connected_templates_count)
  end

  def new
    @account = current_user.accounts.new(default_account_attributes)
    @initial_snapshot = @account.account_snapshots.new(recorded_on: Date.current)
    @credit_card_payment_schedule = build_credit_card_payment_schedule_form(@account)
    @credit_card_payment_schedule_enabled = false
  end

  def create
    result = create_account
    assign_account_creation_result(result)

    if result.success?
      redirect_to @account, notice: result.notice
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

  def create_account
    Accounts::Creator.call(
      user: current_user,
      account_params: account_params,
      initial_snapshot_params: initial_snapshot_params,
      credit_card_payment_schedule_params: credit_card_payment_schedule_params
    )
  end

  def assign_account_creation_result(result)
    @account = result.account
    @initial_snapshot = result.initial_snapshot || @account.account_snapshots.new(recorded_on: Date.current)
    @credit_card_payment_schedule = result.credit_card_payment_schedule || build_credit_card_payment_schedule_form(@account)
    @credit_card_payment_schedule_enabled = credit_card_payment_schedule_enabled?
  end

  def credit_card_payment_schedule_enabled?
    @account.credit_card? && ActiveModel::Type::Boolean.new.cast(credit_card_payment_schedule_params[:enabled])
  end

  def account_params
    params.require(:account).permit(:name, :institution_name, :kind, :active, :include_in_net_worth, :include_in_cash, :notes)
  end
end
