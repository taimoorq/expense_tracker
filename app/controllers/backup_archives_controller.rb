require "digest"

class BackupArchivesController < ApplicationController
  include AutomaticBackupAccess

  def show
    workspace = automatic_backup_workspace!
    archive = workspace.backup_archives.state_ready.find(params.expect(:id))
    configuration = Platform::Backup::ArchiveConfiguration.current
    raise Platform::Backup::Storage::Error, configuration.error unless configuration.ready?
    unless archive.storage_adapter == configuration.driver
      raise Platform::Backup::Storage::Error, "The archive storage driver is no longer configured."
    end

    contents = Platform::Backup::Storage.build(configuration).read(archive.storage_key)
    unless contents && contents.bytesize == archive.byte_size && Digest::SHA256.hexdigest(contents) == archive.archive_checksum
      raise Platform::Backup::Storage::Error, "The stored archive could not be verified."
    end

    send_data contents,
      filename: archive.filename,
      type: archive.content_type,
      disposition: "attachment"
  rescue Platform::Backup::Storage::Error => error
    redirect_to backup_restore_path, alert: error.message
  end
end
