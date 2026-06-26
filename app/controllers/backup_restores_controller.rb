class BackupRestoresController < ApplicationController
  include BackupRestoreFlow

  def show
    prepare_backup_restore_page
  end

  def export
    render_backup_export
  end

  def sample
    sample_backup = Platform::UserDataSampleBackup.new

    send_data sample_backup.to_json,
      filename: sample_backup.filename,
      type: "application/json; charset=utf-8",
      disposition: "attachment"
  end

  def preview
    render_backup_preview
  end

  def import
    render_backup_import
  end
end
