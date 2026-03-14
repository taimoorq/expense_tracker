class AccountSnapshotsController < ApplicationController
  def create
    @account = current_user.accounts.find(params[:account_id])
    @account_snapshot = @account.account_snapshots.new(account_snapshot_params)

    if @account_snapshot.save
      redirect_to @account, notice: "Balance snapshot recorded."
    else
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
      redirect_to @account, notice: "Balance snapshot updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @account = current_user.accounts.find(params[:account_id])
    @account_snapshot = @account.account_snapshots.find(params[:id])
    @account_snapshot.destroy!

    redirect_to @account, notice: "Balance snapshot deleted."
  end

  private

  def account_snapshot_params
    params.require(:account_snapshot).permit(:recorded_on, :balance, :available_balance, :notes)
  end
end
