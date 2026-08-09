module BackupRestoreFlow
  extend ActiveSupport::Concern

  private

  def render_backup_export
    exporter = build_backup_exporter(selected_scopes(:export_scopes))
    export_password = params[:export_password].to_s

    return redirect_to backup_restore_path, alert: "Choose at least one section to export." if exporter.scopes.empty?
    return redirect_to backup_restore_path, alert: "Use an export password with at least 8 characters." if export_password.present? && export_password.length < 8

    if exporter.is_a?(Platform::Backup::V2::Exporter)
      dispatched = Platform::Backup::V2::ExportDispatch.call(
        user: current_user,
        scopes: exporter.scopes,
        password: export_password.presence
      )
      redirect_to operation_run_path(dispatched.operation), notice: "Backup export queued. The download will appear when it is ready."
      return
    end

    send_data exporter.backup_json(password: export_password.presence),
      filename: exporter.filename(password: export_password.presence),
      type: "application/json; charset=utf-8",
      disposition: "attachment"
  end

  def render_backup_preview
    return redirect_to backup_restore_path, alert: "Choose a backup file before previewing the import." if params[:file].blank?

    parsed = Platform::UserDataBackupCodec.decode(source: params[:file], password: params[:import_password].to_s.presence)
    return redirect_to backup_restore_path, alert: "Import preview failed: #{parsed[:error]}" unless parsed[:success]

    import_scopes = dependency_safe_import_scopes(selected_scopes(:import_scopes), payload: parsed[:payload])
    preview = Platform::UserDataImportPreview.new(payload: parsed[:payload], scopes: import_scopes).call
    return redirect_to backup_restore_path, alert: "Import preview failed: #{preview[:error]}" unless preview[:success]

    prepare_backup_restore_page(selected_import_scopes: preview[:summary][:selected_scopes])
    @import_preview = build_import_preview(
      payload: parsed[:payload],
      scopes: preview[:summary][:selected_scopes],
      encrypted: parsed[:encrypted]
    )

    render :show
  end

  def render_backup_import
    preview_token = restore_commit_parameters.fetch(:preview_token)
    restore_draft = preview_store.load_draft(preview_token)
    preview_data = restore_draft&.preview_data
    return redirect_to backup_restore_path, alert: "Import preview expired. Preview the backup again before restoring." unless preview_data
    return render_sample_backup_confirmation(preview_data) if sample_backup_confirmation_required?(preview_data)
    return render_v2_replacement_confirmation(preview_data) if v2_replacement_confirmation_required?(preview_data)

    if preview_data.fetch(:payload).fetch(:version).to_i == 2
      operation = Platform::Backup::V2::Dispatch.call(
        draft: restore_draft,
        replace_existing: confirmed_v2_replacement?(preview_data)
      )
      redirect_to operation_run_path(operation), notice: "Backup restore queued. You can safely leave this page."
      return
    end

    result = Platform::UserDataImport.new(
      user: current_user,
      payload: preview_data.fetch(:payload),
      scopes: preview_data.fetch(:scopes),
      replace_existing: confirmed_v2_replacement?(preview_data)
    ).call

    if result[:success]
      preview_store.clear(preview_token)
      checkpoint_notice = result[:checkpoint_id].present? ? " A recoverable checkpoint is available below for seven days." : ""
      redirect_to backup_restore_path, notice: "#{Platform::BackupRestoreImportNotice.build(counts: result[:counts])}#{checkpoint_notice}"
    else
      redirect_to backup_restore_path, alert: "Import failed: #{result[:error]}"
    end
  rescue Platform::Backup::V2::Dispatch::InvalidDraft
    redirect_to backup_restore_path, alert: "Import preview expired. Preview the backup again before restoring."
  end

  def sample_backup_confirmation_required?(preview_data)
    preview_data.fetch(:payload)[:sample_backup] == true && restore_commit_parameters[:confirm_sample_backup] != "1"
  end

  def render_sample_backup_confirmation(preview_data)
    prepare_backup_restore_page(selected_import_scopes: preview_data.fetch(:scopes))
    @import_preview = build_import_preview(
      payload: preview_data.fetch(:payload),
      scopes: preview_data.fetch(:scopes),
      encrypted: preview_data.fetch(:encrypted),
      token: restore_commit_parameters.fetch(:preview_token)
    )
    flash.now[:alert] = "Confirm that you want to import the reference-only sample backup before restoring it."
    render :show, status: :unprocessable_content
  end

  def v2_replacement_confirmation_required?(preview_data)
    v2_replacement_required?(preview_data) && restore_commit_parameters[:confirm_replace_existing] != "1"
  end

  def render_v2_replacement_confirmation(preview_data)
    prepare_backup_restore_page(selected_import_scopes: preview_data.fetch(:scopes))
    @import_preview = build_import_preview(
      payload: preview_data.fetch(:payload),
      scopes: preview_data.fetch(:scopes),
      encrypted: preview_data.fetch(:encrypted),
      token: restore_commit_parameters.fetch(:preview_token)
    )
    flash.now[:alert] = "Confirm replacement. The app will create an encrypted recovery checkpoint before changing financial data."
    render :show, status: :unprocessable_content
  end

  def selected_scopes(param_key)
    Array(params.permit(param_key => [])[param_key]).reject(&:blank?)
  end

  def dependency_safe_import_scopes(scopes, payload:)
    scopes = Array(scopes)
    if payload.with_indifferent_access[:version].to_i == 2 && (scopes & Platform::Backup::V2::Preview::FINANCIAL_SCOPES).any?
      scopes |= Platform::Backup::V2::Preview::FINANCIAL_SCOPES
    end
    return scopes unless scopes.include?("account_activity")
    return scopes if scopes.include?("accounts")
    return scopes if missing_account_activity_accounts(payload).empty?

    scopes - [ "account_activity" ]
  end

  def missing_account_activity_accounts(payload)
    payload = payload.with_indifferent_access
    activity_account_names = Array(payload.dig(:data, :account_activity)).filter_map { |attributes| attributes[:account].presence }.uniq
    return [] if activity_account_names.empty?

    existing_names = current_user.accounts.where(name: activity_account_names).pluck(:name)
    activity_account_names - existing_names
  end

  def prepare_backup_restore_page(selected_import_scopes: Platform::UserDataExport::SCOPES)
    @scope_cards = Platform::BackupRestoreScopeCatalog.new(user: current_user).call
    @selected_export_scopes = Platform::UserDataExport::SCOPES
    @selected_import_scopes = selected_import_scopes
    @target_backup_v2 = target_backup_workspace&.target_reads_enabled?
    @restore_checkpoints = target_backup_workspace&.restore_checkpoints&.available&.order(created_at: :desc)&.limit(5) || []
  end

  def build_import_preview(payload:, scopes:, encrypted:, token: nil)
    preview = Platform::UserDataImportPreview.new(payload: payload, scopes: scopes).call

    preview.fetch(:summary).merge(
      encrypted: encrypted,
      format_version: payload[:version].to_i,
      token: token || preview_store.store(payload: payload, scopes: scopes, encrypted: encrypted),
      replacement_required: payload[:version].to_i == 2 && Platform::Backup::ReplacementState.any?(user: current_user, scopes: scopes)
    )
  end

  def confirmed_v2_replacement?(preview_data)
    return false unless v2_replacement_required?(preview_data)

    restore_commit_parameters[:confirm_replace_existing] == "1"
  end

  def restore_commit_parameters
    @restore_commit_parameters ||= params.permit(:confirm_sample_backup, :confirm_replace_existing).to_h.symbolize_keys.merge(
      preview_token: params.expect(:preview_token)
    )
  end


  def v2_replacement_required?(preview_data)
    preview_data.fetch(:payload)[:version].to_i == 2 &&
      Platform::Backup::ReplacementState.any?(user: current_user, scopes: preview_data.fetch(:scopes))
  end

  def build_backup_exporter(scopes)
    return Platform::UserDataExport.new(user: current_user, scopes: scopes) unless target_backup_workspace&.target_reads_enabled?

    expanded_scopes = Array(scopes)
    if (expanded_scopes & Platform::Backup::V2::Preview::FINANCIAL_SCOPES).any?
      expanded_scopes |= Platform::Backup::V2::Preview::FINANCIAL_SCOPES
    end
    Platform::Backup::V2::Exporter.new(user: current_user, scopes: expanded_scopes)
  end

  def target_backup_workspace
    @target_backup_workspace ||= BudgetWorkspace.find_by(legacy_owner_user_id: current_user.id)
  end

  def preview_store
    @preview_store ||= Platform::BackupRestorePreviewStore.new(user: current_user)
  end
end
