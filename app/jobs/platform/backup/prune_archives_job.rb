module Platform
  module Backup
    class PruneArchivesJob < ApplicationJob
      queue_as :maintenance
      retry_on Storage::Error, wait: :polynomially_longer, attempts: 5, report: true

      def perform(workspace_id)
        workspace = BudgetWorkspace.find(workspace_id)
        configuration = ArchiveConfiguration.current
        raise Storage::Error, configuration.error unless configuration.ready?

        storage = Storage.build(configuration)
        retention_count = workspace.backup_schedule&.retention_count || BackupSchedule::RETENTION_OPTIONS.second
        candidates = workspace.backup_archives.state_ready.order(verified_at: :desc).offset(retention_count)
        candidates.to_a.each { |archive| delete_archive(archive, storage, configuration) }
        workspace.backup_archives.state_deleting.find_each do |archive|
          delete_archive(archive, storage, configuration)
        end
      end

      private

      def delete_archive(archive, storage, configuration)
        unless archive.storage_adapter == configuration.driver
          raise Storage::Error, "The archive storage driver is no longer configured"
        end

        archive.with_lock do
          return if archive.state_deleted?
          archive.begin_deleting! if archive.state_ready?
          return unless archive.state_deleting?
        end
        return unless storage.delete(archive.storage_key)

        archive.with_lock do
          archive.mark_deleted! if archive.state_deleting?
        end
        Platform::OperationalEvents.notify(
          "backup_archive.deleted",
          workspace_id: archive.budget_workspace_id,
          archive_id: archive.id
        )
      end
    end
  end
end
