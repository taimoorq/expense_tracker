class AccountSnapshotsController < ApplicationController
  def create
    @account = current_user.accounts.find(params[:account_id])
    @account_snapshot = @account.account_snapshots.new(account_snapshot_params)

    if @account_snapshot.save
      redirect_to account_path(@account, view: "manage"), notice: "Balance snapshot recorded."
    else
      assign_manage_page
      render "accounts/show", status: :unprocessable_entity
    end
  end

  def edit
    @account = current_user.accounts.find(params[:account_id])
    @account_snapshot = @account.account_snapshots.find(params[:id])
  end

  def update
    @account = current_user.accounts.find(params[:account_id])
    @account_snapshot = @account.account_snapshots.find(params[:id])

    if @account_snapshot.update(account_snapshot_params)
      redirect_to account_path(@account, view: "manage"), notice: "Balance snapshot updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @account = current_user.accounts.find(params[:account_id])
    @account_snapshot = @account.account_snapshots.find(params[:id])
    @account_snapshot.destroy!

    redirect_to account_path(@account, view: "manage"), notice: "Balance snapshot deleted."
  end

  private

  def assign_manage_page
    detail_page = Accounts::DetailPage.new(account: @account, view: "manage").call
    @account_view = "manage"
    @selected_range = Accounts::MovementTimeline::DEFAULT_RANGE
    @balance_summary = detail_page.fetch(:balance_summary)
    @account_story = detail_page.fetch(:account_story)
    @balance_history_rows = detail_page.fetch(:balance_history_rows)
    @connected_templates = detail_page.fetch(:connected_templates)
    @connected_templates_count = detail_page.fetch(:connected_templates_count)
    @import_history = detail_page.fetch(:import_history)
  end

  def account_snapshot_params
    params.require(:account_snapshot).permit(:recorded_on, :balance, :available_balance, :notes)
  end
end
