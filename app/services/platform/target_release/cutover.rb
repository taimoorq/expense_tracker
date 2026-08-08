module Platform
  module TargetRelease
    class Cutover
      Result = Data.define(:workspace, :operation_run, :action, :comparison_count) do
        def as_json(*)
          {
            workspace_id: workspace.id,
            operation_run_id: operation_run.id,
            action: action,
            comparison_count: comparison_count,
            target_writes_enabled: workspace.target_writes_enabled?,
            target_reads_enabled: workspace.target_reads_enabled?
          }
        end
      end

      ACTIONS = %w[enable rollback].freeze

      def self.call(workspace:, actor_membership:, action:, change_id:)
        new(
          workspace: workspace,
          actor_membership: actor_membership,
          action: action,
          change_id: change_id
        ).call
      end

      def initialize(workspace:, actor_membership:, action:, change_id:)
        @workspace = workspace
        @actor_membership = actor_membership
        @action = action.to_s
        @change_id = change_id.to_s
      end

      def call
        raise ArgumentError, "Unsupported target cutover action." unless action.in?(ACTIONS)
        raise ArgumentError, "A deployment change ID is required." if change_id.blank?

        Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: actor_membership)
        outcome = Platform::Operations::Executor.call(
          workspace: workspace,
          actor_membership: actor_membership,
          operation_type: "target_read_#{action}",
          idempotency_key: change_id,
          request: { workspace_id: workspace.id, action: action, change_id: change_id },
          redacted_parameters: { "action" => action },
          retryable: true,
          on_replay: ->(_reference) { workspace.reload }
        ) do |operation|
          comparison_count = apply_change!
          Audit::Recorder.call(
            workspace: workspace,
            actor_membership: actor_membership,
            operation_run: operation,
            entity: workspace,
            action: "access_change",
            changed_fields: %i[target_writes_enabled target_reads_enabled]
          )
          Platform::Operations::Executor::Completion.new(
            value: workspace.reload,
            result_counts: { "comparison_count" => comparison_count },
            result_reference: { "type" => "BudgetWorkspace", "id" => workspace.id }
          )
        end
        Result.new(
          workspace: outcome.value,
          operation_run: outcome.operation_run,
          action: action,
          comparison_count: outcome.operation_run.result_counts.fetch("comparison_count")
        )
      end

      private

      attr_reader :action, :actor_membership, :change_id, :workspace

      def apply_change!
        return enable! if action == "enable"

        rollback!
      end

      def enable!
        eligibility = Eligibility.call(workspace: workspace)
        workspace.update!(target_writes_enabled: true) unless workspace.target_writes_enabled?
        workspace.update!(target_reads_enabled: true) unless workspace.target_reads_enabled?
        eligibility.comparison_count
      end

      def rollback!
        workspace.update!(target_reads_enabled: false) if workspace.target_reads_enabled?
        0
      end
    end
  end
end
