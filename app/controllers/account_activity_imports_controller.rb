class AccountActivityImportsController < ApplicationController
  before_action :set_account

  def new
  end

  def preview
    if params[:file].blank?
      redirect_to new_account_account_activity_import_path(@account), alert: "Choose a CSV file to preview."
      return
    end

    @preview = Accounts::ActivityImports::PreviewBuilder.new(user: current_user, account: @account, file: params[:file]).call
    @preview_token = preview_store.store(@preview) if @preview[:ok]

    render :preview, status: @preview[:ok] ? :ok : :unprocessable_content
  end

  def create
    preview_data = preview_store.load(params[:preview_token])
    unless preview_data
      redirect_to new_account_account_activity_import_path(@account), alert: "Activity preview expired. Preview the file again before importing."
      return
    end
    preview_data = preview_data.deep_symbolize_keys

    unless preview_data[:account_id].to_s == @account.id
      redirect_to new_account_account_activity_import_path(@account), alert: "Activity preview does not match this account."
      return
    end

    result = Accounts::ActivityImports::Importer.new(user: current_user, account: @account, preview: preview_data).call

    if result[:ok]
      preview_store.clear(params[:preview_token])
      redirect_to account_path(@account), notice: import_success_notice(result)
    else
      redirect_to new_account_account_activity_import_path(@account), alert: "Import failed: #{result[:error]}"
    end
  end

  private

  def set_account
    @account = current_user.accounts.find(params[:account_id])
  end

  def preview_store
    @preview_store ||= Accounts::ActivityImports::PreviewStore.new(user: current_user)
  end

  def import_success_notice(result)
    details = []
    duplicate_count = result[:duplicate_count].to_i
    warning_count = Array(result[:warnings]).size
    details << "#{duplicate_count} duplicate row#{'s' unless duplicate_count == 1} skipped" if duplicate_count.positive?
    details << "#{warning_count} import warning#{'s' unless warning_count == 1}" if warning_count.positive?
    base = "Activity import complete: #{result[:imported_count]} row#{'s' unless result[:imported_count] == 1} imported."
    source_message = if result[:import]&.institution_balance?
      "Institution balance is now the trusted balance source."
    else
      "Activity rows are saved and will apply once the account has a trusted balance source."
    end
    return "#{base} #{source_message}" if details.empty?

    "#{base} #{details.join(', ')}. #{source_message}"
  end
end
