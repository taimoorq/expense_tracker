class AccountsController < ApplicationController
  include AccountSetup

  DETAIL_VIEWS = %w[overview activity insights manage].freeze

  def index
    summary = Accounts::Summary.new(user: current_user, include_trend: true).call
    @accounts = summary.fetch(:accounts)
    @account_balance_rows = summary.fetch(:account_balance_rows)
    @account = current_user.accounts.new
    @net_worth_accounts = summary.fetch(:net_worth_accounts)
    @assets_total = summary.fetch(:assets_total)
    @liabilities_total = summary.fetch(:liabilities_total)
    @net_worth_total = summary.fetch(:net_worth_total)
    @latest_snapshot = summary.fetch(:latest_snapshot)
    @latest_balance_source = summary.fetch(:latest_balance_source)
    @accounts_with_balance_sources_count = summary.fetch(:accounts_with_balance_sources_count)
    @accounts_missing_balance_sources_count = summary.fetch(:accounts_missing_balance_sources_count)
    @accounts_with_snapshots_count = summary.fetch(:accounts_with_snapshots_count)
    @accounts_missing_snapshots_count = summary.fetch(:accounts_missing_snapshots_count)
    @trend_labels = summary.fetch(:trend_labels)
    @trend_values = summary.fetch(:trend_values)
  end

  def show
    @account = current_user.accounts.includes(:account_snapshots).find(params[:id])
    @account_snapshot = AccountSnapshot.new(account: @account, recorded_on: Date.current)
    @account_view = params[:view].to_s.in?(DETAIL_VIEWS) ? params[:view].to_s : "overview"
    detail_page = Accounts::DetailPage.new(account: @account, range: params[:range], view: @account_view).call
    @balance_summary = detail_page.fetch(:balance_summary)
    @account_story = detail_page.fetch(:account_story)
    @selected_range = params[:range].to_s.in?(Accounts::MovementTimeline::RANGE_OPTIONS.keys) ? params[:range].to_s : Accounts::MovementTimeline::DEFAULT_RANGE
    @balance_history_rows = detail_page[:balance_history_rows]
    @credit_card_progress = detail_page[:credit_card_progress]
    @connected_templates = detail_page[:connected_templates]
    @connected_templates_count = detail_page[:connected_templates_count]
    @activity_insights = detail_page[:activity_insights]
    @import_history = detail_page[:import_history]
    @movement_timeline = detail_page[:movement_timeline]
    @recent_activity = detail_page[:recent_activity]
    @activity_ledger = Accounts::ActivityLedgerQuery.new(account: @account, filters: activity_ledger_filters).call if @account_view == "activity"
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

  def activity_ledger_filters
    params.permit(:source, :direction, :starts_on, :ends_on, :merchant, :classification)
  end

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
