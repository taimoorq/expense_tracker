module Accounts
  module ActivityImports
    class Dispatch
      OPERATION_TYPE = "commit_legacy_account_activity_import".freeze
      JOB_CLASS = "Accounts::ActivityImports::CommitJob".freeze

      def self.call(draft:)
        new(draft: draft).call
      end

      def initialize(draft:)
        @draft = draft
      end

      def call
        raise InvalidDraft, "The activity preview cannot be queued" unless draft.dispatchable?

        existing = existing_operation
        return reuse_existing(existing) if existing

        Platform::Operations::Dispatcher.call(
          workspace: draft.budget_workspace,
          actor_membership: membership,
          operation_type: OPERATION_TYPE,
          idempotency_key: draft.idempotency_key,
          request: draft.operation_request,
          redacted_parameters: draft.redacted_operation_parameters,
          job_class: JOB_CLASS,
          job_arguments: [ draft.id ],
          retryable: true
        ) do |operation|
          draft.queue!(operation_run: operation)
        end
      end

      private

      attr_reader :draft

      def existing_operation
        draft.budget_workspace.operation_runs.find_by(
          operation_type: OPERATION_TYPE,
          idempotency_key: draft.idempotency_key
        )
      end

      def reuse_existing(operation)
        expected_digest = Platform::Operations::RequestDigest.for(draft.operation_request)
        return reuse_legacy_operation(operation, expected_digest) if operation.job_class.blank?

        unless operation.request_digest == expected_digest
          raise Platform::Operations::Executor::IdempotencyConflict,
            "The idempotency key was already used for a different request"
        end

        attached_draft = operation.account_activity_import_draft
        if attached_draft && attached_draft != draft
          draft.expire! if draft.state_previewed? || draft.state_failed?
          Platform::Operations::Dispatcher.enqueue(operation) if operation.dispatched?
          return operation
        end

        draft.queue!(operation_run: operation) unless draft.state_queued?
        Platform::Operations::Dispatcher.enqueue(operation)
        operation
      end

      def reuse_legacy_operation(operation, expected_digest)
        unless operation.state_failed? && operation.retryable?
          draft.expire! if draft.state_previewed? || draft.state_failed?
          return operation
        end

        operation.with_lock do
          operation.update!(
            request_digest: expected_digest,
            redacted_parameters: draft.redacted_operation_parameters,
            job_class: JOB_CLASS,
            job_arguments: [ draft.id ],
            state: "pending",
            completed_at: nil,
            error_code: nil,
            enqueued_at: nil,
            last_enqueue_attempt_at: nil
          )
          draft.queue!(operation_run: operation)
        end
        Platform::Operations::Dispatcher.enqueue(operation)
        operation
      end

      def membership
        draft.budget_workspace.workspace_memberships.status_active.find_by!(user: draft.user)
      end

      class InvalidDraft < StandardError; end
    end
  end
end
