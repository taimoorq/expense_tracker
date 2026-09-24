class ActivityController < ApplicationController
  def import
    @accounts = current_user.accounts.active_first.order(:name)
    if params[:continue] == "1" && params[:account_id].present?
      account = @accounts.find(params[:account_id])
      redirect_to new_account_account_activity_import_path(account)
    end
  end

  def index
    @activity = Activity::IndexQuery.call(
      user: current_user,
      view: params[:view],
      account_id: params[:account_id],
      starts_on: params[:starts_on],
      ends_on: params[:ends_on],
      direction: params[:direction],
      transaction_id: params[:transaction_id], page: params[:page], source: params[:source]
    )
    @workspace = BudgetWorkspace.find_by(legacy_owner_user: current_user)
    if @workspace
      @accounts = @activity.accounts
      @bank_review = Activity::BankReviewQuery.new(workspace: @workspace, user: current_user, account_id: @activity.account_id, starts_on: @activity.starts_on, ends_on: @activity.ends_on, page: params[:bank_page], pending: @activity.view == "pending", ignored: @activity.view == "ignored")
      @transactions = @bank_review.transactions
      @accepted_transactions = @bank_review.accepted_transactions
      @entries = @bank_review.entries
      @transfer_candidates = @bank_review.transfer_candidates
      @manual_settlements = PaymentSettlement.where(budget_workspace: @workspace).joins(:financial_transaction).where(financial_transactions: { origin_kind: "manual", state: "posted" }).includes(:financial_transaction, payment_commitment: :account).order(created_at: :desc).limit(25)
      @commitments = @workspace.payment_commitments.where(state: "reserved").includes(:account, :expense_entry, :payment_settlements).order(:initiated_on)
      @commitments = @commitments.where(account_id: @activity.account_id) if @activity.account_id
      @commitments = @commitments.where(initiated_on: @activity.starts_on..) if @activity.starts_on
      @commitments = @commitments.where(initiated_on: ..@activity.ends_on) if @activity.ends_on
      @manual_settlements = @manual_settlements.joins(:payment_commitment).where(payment_commitments: { account_id: @activity.account_id }) if @activity.account_id
      @manual_settlements = @manual_settlements.where(financial_transactions: { effective_on: @activity.starts_on.. }) if @activity.starts_on
      @manual_settlements = @manual_settlements.where(financial_transactions: { effective_on: ..@activity.ends_on }) if @activity.ends_on
    end
  end
end
