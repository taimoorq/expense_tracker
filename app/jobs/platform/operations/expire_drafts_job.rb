module Platform
  module Operations
    class ExpireDraftsJob < ApplicationJob
      queue_as :maintenance

      def perform
        AccountActivityImportDraft
          .where(state: %w[previewed failed], expires_at: ...Time.current)
          .find_each(&:expire!)
        BackupRestoreDraft
          .where(state: %w[previewed failed], expires_at: ...Time.current)
          .find_each(&:expire!)
        BackupExportArtifact
          .where(state: %w[ready failed], expires_at: ...Time.current)
          .find_each(&:expire!)
      end
    end
  end
end
