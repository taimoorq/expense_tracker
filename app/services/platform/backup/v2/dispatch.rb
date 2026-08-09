module Platform
  module Backup
    module V2
      class Dispatch
        OPERATION_TYPE = "backup_v2_restore".freeze
        JOB_CLASS = "Platform::Backup::V2::RestoreJob".freeze

        def self.call(draft:, replace_existing:)
          new(draft: draft, replace_existing: replace_existing).call
        end

        def initialize(draft:, replace_existing:)
          @draft = draft
          @replace_existing = replace_existing
        end

        def call
          raise InvalidDraft, "The staged backup cannot be queued" unless draft.dispatchable?

          draft.replacement_requested = replace_existing
          existing = existing_operation
          return reuse_existing(existing) if existing

          Platform::Operations::Dispatcher.call(
            workspace: draft.budget_workspace,
            actor_membership: membership,
            operation_type: OPERATION_TYPE,
            idempotency_key: idempotency_key,
            request: draft.operation_request,
            redacted_parameters: draft.redacted_operation_parameters,
            job_class: JOB_CLASS,
            job_arguments: [ draft.id ],
            retryable: true
          ) do |operation|
            transfer = draft.data_transfer_run || build_transfer(operation)
            draft.queue!(
              operation_run: operation,
              data_transfer_run: transfer,
              replacement_requested: replace_existing
            )
          end
        end

        private

        attr_reader :draft, :replace_existing

        def existing_operation
          draft.budget_workspace.operation_runs.find_by(
            operation_type: OPERATION_TYPE,
            idempotency_key: idempotency_key
          )
        end

        def reuse_existing(operation)
          expected_digest = Platform::Operations::RequestDigest.for(draft.operation_request)
          unless operation.request_digest == expected_digest && operation.job_class == JOB_CLASS
            raise Platform::Operations::Executor::IdempotencyConflict,
              "The restore idempotency key was already used for a different request"
          end

          attached_draft = operation.backup_restore_draft
          if attached_draft && attached_draft != draft
            draft.expire! if draft.state_previewed? || draft.state_failed?
            Platform::Operations::Dispatcher.enqueue(operation)
            return operation
          end

          transfer = draft.data_transfer_run || build_transfer(operation)
          draft.queue!(
            operation_run: operation,
            data_transfer_run: transfer,
            replacement_requested: replace_existing
          ) unless draft.state_queued?
          Platform::Operations::Dispatcher.enqueue(operation)
          operation
        end

        def build_transfer(operation)
          draft.budget_workspace.data_transfer_runs.create!(
            actor_membership: membership,
            operation_run: operation,
            operation: "restore",
            payload_format_version: "2",
            envelope_version: Platform::UserDataBackupCodec::ENCRYPTED_FORMAT_VERSION.to_s,
            payload_checksum: draft.payload_checksum,
            selected_scopes: draft.selected_scopes,
            checkpoint_reference: replace_existing ? "pending" : "empty-target",
            state: "pending",
            result_counts: {}
          )
        end

        def membership
          draft.budget_workspace.workspace_memberships.status_active.find_by!(user: draft.user)
        end

        def idempotency_key
          "backup-v2:#{draft.payload_checksum}:#{replace_existing ? 'replacement' : 'empty'}"
        end

        class InvalidDraft < StandardError; end
      end
    end
  end
end
