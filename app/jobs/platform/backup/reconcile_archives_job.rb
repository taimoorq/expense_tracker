module Platform
  module Backup
    class ReconcileArchivesJob < ApplicationJob
      queue_as :maintenance

      def perform
        workspace_ids = BackupArchive.state_deleting.distinct.pluck(:budget_workspace_id)
        workspace_ids.each { |workspace_id| PruneArchivesJob.perform_later(workspace_id) }
      end
    end
  end
end
