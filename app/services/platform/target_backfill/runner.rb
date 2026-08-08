module Platform
  module TargetBackfill
    class Runner
      Result = Data.define(:workspace, :operation_run, :verification) do
        def success?
          verification.clean?
        end

        def as_json(*)
          {
            workspace_id: workspace.id,
            operation_run_id: operation_run.id,
            success: success?,
            verification: verification.as_json
          }
        end
      end

      def self.call(user:)
        new(user: user).call
      end

      def initialize(user:)
        @user = user
      end

      def call
        evidence = EvidenceBackfill.call(user: user)
        verification = Verifier.call(
          user: user,
          workspace: evidence.workspace,
          operation_run: evidence.operation_run
        )
        finalize(evidence, verification)

        Result.new(
          workspace: evidence.workspace,
          operation_run: evidence.operation_run,
          verification: verification
        )
      rescue StandardError => error
        mark_failed(error)
        raise
      end

      private

      attr_reader :user

      def finalize(evidence, verification)
        ApplicationRecord.transaction do
          if verification.clean?
            evidence.workspace.update!(
              target_backfill_version: WorkspaceBootstrap::VERSION,
              target_backfilled_at: Time.current
            )
            evidence.operation_run.update!(
              state: "succeeded",
              result_counts: evidence.operation_run.result_counts.merge("verification" => { "clean" => true }),
              completed_at: Time.current,
              error_code: nil
            )
          else
            evidence.operation_run.update!(
              state: "failed",
              result_counts: evidence.operation_run.result_counts.merge("verification" => { "clean" => false }),
              completed_at: Time.current,
              error_code: "target_parity_failed"
            )
          end
        end
      end

      def mark_failed(error)
        workspace = user.legacy_owned_budget_workspace
        operation = workspace&.operation_runs&.find_by(
          operation_type: "target_model_backfill",
          idempotency_key: WorkspaceBootstrap::VERSION
        )
        return if operation.blank?

        operation.update!(
          state: "failed",
          completed_at: Time.current,
          error_code: error.class.name.underscore.tr("/", "_")
        )
      rescue ActiveRecord::RecordInvalid
        nil
      end
    end
  end
end
