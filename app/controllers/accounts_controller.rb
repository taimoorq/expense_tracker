class AccountsController < ApplicationController
  include AccountSetup
  include AccountPageSetup

  def index
    load_accounts_index_page
  end

  def show
    load_account_detail_page
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
      render :new, status: :unprocessable_content
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
      render :edit, status: :unprocessable_content
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
