module Platform
  module Operations
    class ExpireDraftsJob < ApplicationJob
      queue_as :maintenance

      BATCH_SIZE = 100
      MAX_BATCHES_PER_SCOPE = 10

      def perform
        now = Time.current
        expire_in_batches(
          AccountActivityImportDraft.where(state: %w[previewed failed], expires_at: ...now),
          { preview_payload: {} }, now
        )
        expire_in_batches(
          BackupRestoreDraft.where(state: %w[previewed failed], expires_at: ...now),
          { encrypted_payload: "" }, now
        )
        expire_in_batches(
          BackupExportArtifact.where(state: %w[ready failed], expires_at: ...now),
          { encrypted_contents: nil, encrypted_export_password: nil, ready_at: nil }, now
        )
        expire_checkpoints(now)
      end

      private

      def expire_in_batches(scope, cleared_attributes, now)
        update_in_batches(scope, cleared_attributes.merge(
          state: "expired", failed_at: nil, expired_at: now, updated_at: now
        ))
      end

      def expire_checkpoints(now)
        # A queued restore may need its original recovery snapshot on retry,
        # even when the normal seven-day availability window has elapsed.
        protected_ids = BackupRestoreDraft.state_queued.where.not(restore_checkpoint_id: nil).select(:restore_checkpoint_id)
        scope = RestoreCheckpoint.where(expires_at: ...now).where.not(id: protected_ids)
        update_in_batches(scope.state_ready, state: "expired", encrypted_payload: "", updated_at: now)
        # Preserve the audited rollback timestamp and terminal state.
        update_in_batches(scope.state_restored.where.not(encrypted_payload: ""), encrypted_payload: "", updated_at: now)
      end

      def update_in_batches(scope, attributes)
        MAX_BATCHES_PER_SCOPE.times do
          ids = scope.order(:id).limit(BATCH_SIZE).pluck(:id)
          break if ids.empty?

          # Keep the eligibility predicate on the UPDATE: dispatch may have
          # queued a selected draft. update_all also advances lock_version so
          # a stale model cannot restore the payload after expiry.
          scope.where(id: ids).update_all(attributes)
        end
      end
    end
  end
end
