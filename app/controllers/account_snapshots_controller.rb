class AccountSnapshotsController < ApplicationController
  def new
    @account = current_user.accounts.find(params[:account_id])
    @account_snapshot = @account.account_snapshots.new(recorded_on: Date.current)

    render_inline_editor if turbo_frame_request?
  end

  def create
    @account = current_user.accounts.find(params[:account_id])
    @account_snapshot = Accounts::SnapshotWriter.create(account: @account, attributes: account_snapshot_params)

    if @account_snapshot.persisted? && @account_snapshot.errors.none?
      respond_with_snapshot_success("Balance snapshot recorded.")
    elsif turbo_frame_request?
      render_inline_editor(status: :unprocessable_content)
    else
      assign_manage_page
      render "accounts/show", status: :unprocessable_content
    end
  end

  def edit
    @account = current_user.accounts.find(params[:account_id])
    @account_snapshot = @account.account_snapshots.find(params[:id])

    render_inline_editor if turbo_frame_request?
  end

  def update
    @account = current_user.accounts.find(params[:account_id])
    @account_snapshot = @account.account_snapshots.find(params[:id])

    if Accounts::SnapshotWriter.update(snapshot: @account_snapshot, attributes: account_snapshot_params)
      respond_with_snapshot_success("Balance snapshot updated.")
    elsif turbo_frame_request?
      render_inline_editor(status: :unprocessable_content)
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @account = current_user.accounts.find(params[:account_id])
    @account_snapshot = @account.account_snapshots.find(params[:id])
    if Accounts::SnapshotWriter.destroy(snapshot: @account_snapshot)
      redirect_to account_path(@account, view: "manage"), notice: "Balance snapshot deleted."
    else
      redirect_to account_path(@account, view: "manage"), alert: @account_snapshot.errors.full_messages.to_sentence
    end
  end

  private

  def respond_with_snapshot_success(message)
    respond_to do |format|
      format.turbo_stream do
        flash[:notice] = message
        render turbo_stream: turbo_stream.refresh(request_id: nil)
      end
      format.html do
        redirect_to account_path(@account, view: "manage"), notice: message, status: :see_other
      end
    end
  end

  def render_inline_editor(status: :ok)
    render partial: "account_snapshots/inline_editor",
      formats: [ :html ],
      locals: {
        account: @account,
        account_snapshot: @account_snapshot,
        frame_id: inline_frame_id
      },
      status: status
  end

  def inline_frame_id
    requested_frame_id = request.headers["Turbo-Frame"].to_s
    return requested_frame_id if requested_frame_id.in?(allowed_inline_frame_ids)

    raise ActionController::BadRequest, "Invalid account snapshot editor frame."
  end

  def allowed_inline_frame_ids
    %w[mobile desktop].map do |surface|
      ActionView::RecordIdentifier.dom_id(@account, "#{surface}_snapshot_editor")
    end
  end

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
