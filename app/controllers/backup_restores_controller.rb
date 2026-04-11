class BackupRestoresController < ApplicationController
  def show
    prepare_backup_restore_page
  end

  def export
    exporter = Platform::UserDataExport.new(user: current_user, scopes: selected_scopes(:export_scopes))
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
    sample_backup = Platform::UserDataSampleBackup.new

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

    parsed = Platform::UserDataBackupCodec.decode(source: params[:file], password: params[:import_password].to_s.presence)
    unless parsed[:success]
      redirect_to backup_restore_path, alert: "Import preview failed: #{parsed[:error]}"
      return
    end

    preview = Platform::UserDataImportPreview.new(payload: parsed[:payload], scopes: selected_scopes(:import_scopes)).call
    unless preview[:success]
      redirect_to backup_restore_path, alert: "Import preview failed: #{preview[:error]}"
      return
    end

    prepare_backup_restore_page(selected_import_scopes: preview[:summary][:selected_scopes])
    @import_preview = build_import_preview(
      payload: parsed[:payload],
      scopes: preview[:summary][:selected_scopes],
      encrypted: parsed[:encrypted]
    )

    render :show
  end

  def import
    preview_data = preview_store.load(params[:preview_token])
    unless preview_data
      redirect_to backup_restore_path, alert: "Import preview expired. Preview the backup again before restoring."
      return
    end

    if preview_data.fetch(:payload)[:sample_backup] == true && params[:confirm_sample_backup] != "1"
      prepare_backup_restore_page(selected_import_scopes: preview_data.fetch(:scopes))
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

    importer = Platform::UserDataImport.new(
      user: current_user,
      payload: preview_data.fetch(:payload),
      scopes: preview_data.fetch(:scopes)
    )

    result = importer.call

    if result[:success]
      preview_store.clear(params[:preview_token])
      redirect_to backup_restore_path, notice: Platform::BackupRestoreImportNotice.build(counts: result[:counts])
    else
      redirect_to backup_restore_path, alert: "Import failed: #{result[:error]}"
    end
  end

  private

  def selected_scopes(param_key)
    Array(params[param_key]).reject(&:blank?)
  end

  def prepare_backup_restore_page(selected_import_scopes: Platform::UserDataExport::SCOPES)
    @scope_cards = Platform::BackupRestoreScopeCatalog.new(user: current_user).call
    @selected_export_scopes = Platform::UserDataExport::SCOPES
    @selected_import_scopes = selected_import_scopes
  end

  def build_import_preview(payload:, scopes:, encrypted:, token: nil)
    preview = Platform::UserDataImportPreview.new(payload: payload, scopes: scopes).call

    preview.fetch(:summary).merge(
      encrypted: encrypted,
      token: token || preview_store.store(payload: payload, scopes: scopes, encrypted: encrypted)
    )
  end

  def preview_store
    @preview_store ||= Platform::BackupRestorePreviewStore.new(user: current_user)
  end
end
