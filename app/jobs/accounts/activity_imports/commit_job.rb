module Accounts
  module ActivityImports
    class CommitJob < ApplicationJob
      include ActiveJob::Continuable

      class InvalidDraft < StandardError; end
      class ImportFailed < StandardError; end

      queue_as :imports
      limits_concurrency(
        key: ->(operation_id, *) { OperationRun.find(operation_id).budget_workspace_id },
        to: 1,
        group: "workspace_mutations",
        duration: 2.hours
      )
      retry_on StandardError, wait: :polynomially_longer, attempts: 5, report: true do |job, error|
        job.send(:mark_exhausted_failure, error)
      end
      discard_on InvalidDraft, report: true do |job, error|
        job.send(:mark_exhausted_failure, error)
      end

      def perform(operation_id, draft_id)
        @operation = OperationRun.find(operation_id)
        @draft = AccountActivityImportDraft.find(draft_id)

        step :validate_draft
        step :commit_import
        step :finalize_progress
      end

      private

      attr_reader :draft, :operation

      def validate_draft
        valid_identity = draft.operation_run_id == operation.id &&
          draft.budget_workspace_id == operation.budget_workspace_id &&
          operation.job_arguments == [ draft.id ]
        raise InvalidDraft, "The queued import identity is invalid" unless valid_identity

        usable_state = draft.state_queued? || (draft.state_consumed? && operation.state_succeeded?)
        raise InvalidDraft, "The queued import is no longer available" unless usable_state

        operation.record_progress!(current: 1, total: 3, label: "Preview validated") unless operation.state_succeeded?
      end

      def commit_import
        outcome = Platform::Operations::Executor.call(
          workspace: operation.budget_workspace,
          actor_membership: operation.actor_membership,
          operation_type: operation.operation_type,
          idempotency_key: operation.idempotency_key,
          request: draft.operation_request,
          redacted_parameters: operation.redacted_parameters,
          retryable: true,
          on_replay: ->(reference) { AccountActivityImport.find(reference.fetch("id")) }
        ) do |running_operation|
          result = Importer.new(
            user: draft.user,
            account: draft.account,
            preview: draft.preview,
            operation_run: running_operation
          ).call
          raise ImportFailed, result.fetch(:error) unless result[:ok]

          running_operation.record_progress!(current: 2, total: 3, label: "Activity rows committed")
          draft.consume!
          Platform::Operations::Executor::Completion.new(
            value: result.fetch(:import),
            result_counts: result_counts(result),
            result_reference: { "type" => "AccountActivityImport", "id" => result.fetch(:import).id }
          )
        end
        @operation = outcome.operation_run
      end

      def finalize_progress
        operation.record_progress!(current: 3, total: 3, label: "Import complete")
      end

      def result_counts(result)
        target_counts = result[:target_completion]&.result_counts || {}
        target_counts.merge(
          "account_activity_imports" => 1,
          "account_activities" => result.fetch(:imported_count),
          "duplicate_rows" => result.fetch(:duplicate_count)
        )
      end

      def mark_exhausted_failure(error)
        @operation ||= OperationRun.find_by(id: arguments.first)
        @draft ||= AccountActivityImportDraft.find_by(id: arguments.second)
        draft&.fail! if draft&.state_queued?
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
