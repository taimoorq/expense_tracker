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

  def new
    @account = current_user.accounts.new(default_account_attributes)
    @initial_snapshot = @account.account_snapshots.new(recorded_on: Date.current)
    @credit_card_payment_schedule = build_credit_card_payment_schedule_form(@account)
    @credit_card_payment_schedule_enabled = false
  end

  def create
    result = Accounts::Creator.call(
      user: current_user,
      account_params: account_params,
      initial_snapshot_params: initial_snapshot_params,
      credit_card_payment_schedule_params: credit_card_payment_schedule_params
    )

    @account = result.account
    @initial_snapshot = result.initial_snapshot || @account.account_snapshots.new(recorded_on: Date.current)
    @credit_card_payment_schedule = result.credit_card_payment_schedule || build_credit_card_payment_schedule_form(@account)
    @credit_card_payment_schedule_enabled = @account.credit_card? && ActiveModel::Type::Boolean.new.cast(credit_card_payment_schedule_params[:enabled])

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

  def account_params
    params.require(:account).permit(:name, :institution_name, :kind, :active, :include_in_net_worth, :include_in_cash, :notes)
  end
end
