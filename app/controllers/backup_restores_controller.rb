class BackupRestoresController < ApplicationController
  PREVIEW_EXPIRATION = 15.minutes
  PREVIEW_STORE = ActiveSupport::Cache.lookup_store(:memory_store)

  def show
    @scope_cards = scope_cards
    @selected_export_scopes = UserDataExport::SCOPES
    @selected_import_scopes = UserDataExport::SCOPES
  end

  def export
    exporter = UserDataExport.new(user: current_user, scopes: selected_scopes(:export_scopes))
    export_password = params[:export_password].to_s

    if exporter.scopes.empty?
      redirect_to backup_restore_path, alert: "Choose at least one section to export."
      return
    end

    if export_password.present? && export_password.length < 8
      redirect_to backup_restore_path, alert: "Use an export password with at least 8 characters."
      return
    end

    send_data exporter.backup_json(password: export_password.presence),
      filename: exporter.filename(password: export_password.presence),
      type: "application/json; charset=utf-8",
      disposition: "attachment"
  end

  def sample
    sample_backup = UserDataSampleBackup.new

    send_data sample_backup.to_json,
      filename: sample_backup.filename,
      type: "application/json; charset=utf-8",
      disposition: "attachment"
  end

  def preview
    if params[:file].blank?
      redirect_to backup_restore_path, alert: "Choose a backup file before previewing the import."
      return
    end

    parsed = UserDataBackupCodec.decode(source: params[:file], password: params[:import_password].to_s.presence)
    unless parsed[:success]
      redirect_to backup_restore_path, alert: "Import preview failed: #{parsed[:error]}"
      return
    end

    preview = UserDataImportPreview.new(payload: parsed[:payload], scopes: selected_scopes(:import_scopes)).call
    unless preview[:success]
      redirect_to backup_restore_path, alert: "Import preview failed: #{preview[:error]}"
      return
    end

    @scope_cards = scope_cards
    @selected_export_scopes = UserDataExport::SCOPES
    @selected_import_scopes = preview[:summary][:selected_scopes]
    @import_preview = build_import_preview(
      payload: parsed[:payload],
      scopes: preview[:summary][:selected_scopes],
      encrypted: parsed[:encrypted]
    )

    render :show
  end

  def import
    preview_data = load_preview(params[:preview_token])
    unless preview_data
      redirect_to backup_restore_path, alert: "Import preview expired. Preview the backup again before restoring."
      return
    end

    if preview_data.fetch(:payload)[:sample_backup] == true && params[:confirm_sample_backup] != "1"
      @scope_cards = scope_cards
      @selected_export_scopes = UserDataExport::SCOPES
      @selected_import_scopes = preview_data.fetch(:scopes)
      @import_preview = build_import_preview(
        payload: preview_data.fetch(:payload),
        scopes: preview_data.fetch(:scopes),
        encrypted: preview_data.fetch(:encrypted),
        token: params[:preview_token]
      )
      flash.now[:alert] = "Confirm that you want to import the reference-only sample backup before restoring it."
      render :show, status: :unprocessable_entity
      return
    end

    importer = UserDataImport.new(
      user: current_user,
      payload: preview_data.fetch(:payload),
      scopes: preview_data.fetch(:scopes)
    )

    result = importer.call

    if result[:success]
      clear_preview(params[:preview_token])
      redirect_to backup_restore_path, notice: import_notice(result[:counts])
    else
      redirect_to backup_restore_path, alert: "Import failed: #{result[:error]}"
    end
  end

  private

  def selected_scopes(param_key)
    Array(params[param_key]).reject(&:blank?)
  end

  def build_import_preview(payload:, scopes:, encrypted:, token: nil)
    preview = UserDataImportPreview.new(payload: payload, scopes: scopes).call

    preview.fetch(:summary).merge(
      encrypted: encrypted,
      token: token || store_preview(payload, scopes, encrypted)
    )
  end

  def store_preview(payload, scopes, encrypted)
    token = SecureRandom.uuid
    PREVIEW_STORE.write(preview_cache_key(token), { payload: payload, scopes: scopes, encrypted: encrypted }, expires_in: PREVIEW_EXPIRATION)
    token
  end

  def load_preview(token)
    return nil if token.blank?

    PREVIEW_STORE.read(preview_cache_key(token))
  end

  def clear_preview(token)
    return if token.blank?

    PREVIEW_STORE.delete(preview_cache_key(token))
  end

  def preview_cache_key(token)
    "backup_restore_preview:#{current_user.id}:#{token}"
  end

  def scope_cards
    {
      "planning_templates" => {
        title: "Planning Templates",
        description: "Paycheck schedules, subscriptions, monthly bills, payment plans, and credit cards.",
        count: current_user.pay_schedules.count + current_user.subscriptions.count + current_user.monthly_bills.count + current_user.payment_plans.count + current_user.credit_cards.count,
        detail: [
          "#{current_user.pay_schedules.count} pay schedules",
          "#{current_user.subscriptions.count} subscriptions",
          "#{current_user.monthly_bills.count} monthly bills",
          "#{current_user.payment_plans.count} payment plans",
          "#{current_user.credit_cards.count} credit cards"
        ].join(" • ")
      },
      "budget_months" => {
        title: "Months",
        description: "Budget months with nested entries, notes, and month-level amounts.",
        count: current_user.budget_months.count,
        detail: "#{current_user.expense_entries.count} entries across #{current_user.budget_months.count} months"
      },
      "accounts" => {
        title: "Accounts",
        description: "Accounts, balances, notes, and recorded snapshots.",
        count: current_user.accounts.count,
        detail: "#{current_user.account_snapshots.count} snapshots across #{current_user.accounts.count} accounts"
      }
    }
  end

  def import_notice(counts)
    parts = []

    if counts[:planning_templates]
      template_counts = counts[:planning_templates]
      total_templates = template_counts.values.sum
      parts << "#{total_templates} planning template#{'s' unless total_templates == 1}"
    end

    if counts[:budget_months]
      month_counts = counts[:budget_months]
      parts << "#{month_counts[:months]} month#{'s' unless month_counts[:months] == 1} and #{month_counts[:entries]} entr#{month_counts[:entries] == 1 ? 'y' : 'ies'}"
    end

    if counts[:accounts]
      account_counts = counts[:accounts]
      parts << "#{account_counts[:accounts]} account#{'s' unless account_counts[:accounts] == 1} and #{account_counts[:snapshots]} snapshot#{'s' unless account_counts[:snapshots] == 1}"
    end

    "Import complete: restored #{parts.join(', ')}."
  end
end
