module Platform
  module Backup
    module V2
      class RestoreJob < ApplicationJob
        include ActiveJob::Continuable

        class InvalidDraft < StandardError; end
        class RestoreFailed < StandardError; end

        queue_as :backups
        limits_concurrency(
          key: ->(operation_id, *) { OperationRun.find(operation_id).budget_workspace_id },
          to: 1,
          group: "workspace_mutations",
          duration: 4.hours
        )
        retry_on StandardError, wait: :polynomially_longer, attempts: 5, report: true do |job, error|
          job.send(:mark_exhausted_failure, error)
        end
        discard_on InvalidDraft, report: true do |job, error|
          job.send(:mark_exhausted_failure, error)
        end

        def perform(operation_id, draft_id)
          @operation = OperationRun.find(operation_id)
          @draft = BackupRestoreDraft.find(draft_id)

          step :validate_stage
          step :create_recovery_checkpoint
          step :activate_restore
          step :finalize_progress
        end

        private

        attr_reader :draft, :operation

        def validate_stage
          valid_identity = draft.operation_run_id == operation.id &&
            draft.budget_workspace_id == operation.budget_workspace_id &&
            operation.job_arguments == [ draft.id ]
          raise InvalidDraft, "The queued restore identity is invalid" unless valid_identity

          usable_state = draft.state_queued? || (draft.state_consumed? && operation.state_succeeded?)
          raise InvalidDraft, "The staged backup is no longer available" unless usable_state

          if draft.state_queued?
            validation = StagingValidator.new(payload: draft.payload, scopes: draft.selected_scopes).call
            raise InvalidDraft, validation.fetch(:error) unless validation[:success]
          end
          operation.record_progress!(current: 1, total: 4, label: "Staged backup verified") unless operation.state_succeeded?
        end

        def create_recovery_checkpoint
          return unless draft.replacement_requested?
          return if draft.restore_checkpoint&.available?

          checkpoint = Platform::Backup::CreateCheckpoint.call(
            user: draft.user,
            scopes: draft.selected_scopes
          )
          draft.update!(restore_checkpoint: checkpoint)
          draft.data_transfer_run.update!(checkpoint_reference: checkpoint.id.to_s)
          operation.record_progress!(current: 2, total: 4, label: "Recovery checkpoint created")
        end

        def activate_restore
          outcome = Platform::Operations::Executor.call(
            workspace: operation.budget_workspace,
            actor_membership: operation.actor_membership,
            operation_type: operation.operation_type,
            idempotency_key: operation.idempotency_key,
            request: draft.operation_request,
            redacted_parameters: operation.redacted_parameters,
            retryable: true,
            on_replay: ->(reference) { DataTransferRun.find(reference.fetch("id")) }
          ) do |running_operation|
            result = Importer.new(
              user: draft.user,
              payload: draft.payload,
              scopes: draft.selected_scopes,
              replace_existing: draft.replacement_requested?,
              checkpoint: draft.restore_checkpoint,
              operation_run: running_operation,
              transfer: draft.data_transfer_run
            ).call
            raise RestoreFailed, result.fetch(:error) unless result[:success]

            running_operation.record_progress!(current: 3, total: 4, label: "Backup activated")
            draft.consume!
            Platform::Operations::Executor::Completion.new(
              value: result.fetch(:transfer),
              result_counts: result.fetch(:counts),
              result_reference: { "type" => "DataTransferRun", "id" => result.fetch(:transfer).id }
            )
          end
          @operation = outcome.operation_run
        end

        def finalize_progress
          operation.record_progress!(current: 4, total: 4, label: "Restore complete")
        end

        def mark_exhausted_failure(error)
          @operation ||= OperationRun.find_by(id: arguments.first)
          @draft ||= BackupRestoreDraft.find_by(id: arguments.second)
          draft&.fail! if draft&.state_queued?
          if draft&.data_transfer_run && !draft.data_transfer_run.state_succeeded?
            draft.data_transfer_run.update!(
              state: "failed",
              completed_at: Time.current,
              error_code: error.class.name.underscore.tr("/", "_")
            )
          end
          return if operation.blank? || operation.state_succeeded?

          operation.update!(
            state: "failed",
            completed_at: Time.current,
            error_code: error.class.name.underscore.tr("/", "_")
          )
        end
      end
    end
  end
end
