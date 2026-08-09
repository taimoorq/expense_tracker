class AccountActivityImportsController < ApplicationController
  before_action :set_account

  def new
    @import_history = import_history
  end

  def preview
    if params[:file].blank?
      redirect_to new_account_account_activity_import_path(@account), alert: "Choose a CSV file to preview."
      return
    end

    @preview = Accounts::ActivityImports::PreviewBuilder.new(user: current_user, account: @account, file: params[:file]).call
    @preview_token = preview_store.store(@preview) if @preview[:ok]
    @import_history = import_history(
      candidate_starts_on: @preview[:started_on],
      candidate_ends_on: @preview[:ended_on]
    )

    render :preview, status: @preview[:ok] ? :ok : :unprocessable_content
  end

  def create
    draft = preview_draft_for_import
    return if draft.blank?

    operation = Accounts::ActivityImports::Dispatch.call(draft: draft)
    redirect_to operation_run_path(operation), notice: "Activity import queued. You can safely leave this page."
  rescue Accounts::ActivityImports::Dispatch::InvalidDraft
    redirect_for_expired_preview
  end

  private

  def set_account
    @account = current_user.accounts.find(params.expect(:account_id))
  end

  def preview_store
    @preview_store ||= Accounts::ActivityImports::PreviewStore.new(user: current_user)
  end

  def preview_draft_for_import
    draft = preview_store.load_draft(preview_token)
    return redirect_for_expired_preview unless draft
    return draft if draft.account_id == @account.id

    redirect_to new_account_account_activity_import_path(@account), alert: "Activity preview does not match this account."
    nil
  end

  def preview_token
    @preview_token ||= params.expect(:preview_token)
  end

  def redirect_for_expired_preview
    redirect_to new_account_account_activity_import_path(@account), alert: "Activity preview expired. Preview the file again before importing."
    nil
  end

  def import_history(candidate_starts_on: nil, candidate_ends_on: nil)
    Accounts::ActivityImports::History.call(
      account: @account,
      candidate_starts_on: candidate_starts_on,
      candidate_ends_on: candidate_ends_on
    )
  end
end
