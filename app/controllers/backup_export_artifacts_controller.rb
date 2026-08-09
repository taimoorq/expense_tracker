class BackupExportArtifactsController < ApplicationController
  def show
    artifact = current_user.backup_export_artifacts.available.find(params.expect(:id))
    send_data artifact.contents,
      filename: artifact.filename,
      type: artifact.content_type,
      disposition: "attachment"
  end
end
