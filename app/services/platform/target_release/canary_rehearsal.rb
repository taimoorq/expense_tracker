module Platform
  module TargetRelease
    class CanaryRehearsal
      Result = Data.define(:workspace, :operation_run, :comparison_count, :smoke_read_count, :flags_restored) do
        def passed?
          operation_run.state_succeeded? && flags_restored
        end

        def as_json(*)
          {
            workspace_id: workspace.id,
            operation_run_id: operation_run.id,
            comparison_count: comparison_count,
            smoke_read_count: smoke_read_count,
            flags_restored: flags_restored,
            passed: passed?
          }
        end
      end

      def self.call(workspace:, rehearsal_id: SecureRandom.uuid)
        new(workspace: workspace, rehearsal_id: rehearsal_id).call
      end

      def initialize(workspace:, rehearsal_id:)
        @workspace = workspace
        @user = workspace.legacy_owner_user
        @rehearsal_id = rehearsal_id.to_s
        @read_window = ReversibleReadWindow.new(workspace: workspace)
      end

      def call
        raise GateFailed, "The workspace does not have a legacy owner." if user.blank?

        membership = workspace.workspace_memberships.status_active.find_by(user: user)
        Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: membership)
        stats = nil
        outcome = Platform::Operations::Executor.call(
          workspace: workspace,
          actor_membership: membership,
          operation_type: "target_read_canary_rehearsal",
          idempotency_key: rehearsal_id,
          request: { workspace_id: workspace.id, rehearsal_id: rehearsal_id },
          redacted_parameters: { "mode" => "local_rehearsal" },
          retryable: true,
          on_replay: ->(_reference) { workspace.reload }
        ) do |operation|
          begin
            operation.record_progress!(current: 0, total: 4, label: "Checking target eligibility")
            eligibility = Eligibility.call(workspace: workspace)
            operation.record_progress!(current: 1, total: 4, label: "Comparing shadow reads")
            comparison_count = eligibility.comparison_count
            operation.record_progress!(current: 2, total: 4, label: "Enabling target reads")
            smoke_read_count = read_window.call do
              operation.record_progress!(current: 3, total: 4, label: "Running target smoke reads")
              run_smoke_reads!
            end
            stats = { "comparison_count" => comparison_count, "smoke_read_count" => smoke_read_count }
          end
          operation.record_progress!(current: 4, total: 4, label: "Rollback verified")
          Audit::Recorder.call(
            workspace: workspace,
            actor_membership: membership,
            operation_run: operation,
            entity: workspace,
            action: "access_change",
            changed_fields: %i[target_writes_enabled target_reads_enabled]
          )
          Platform::Operations::Executor::Completion.new(
            value: workspace.reload,
            result_counts: stats,
            result_reference: { "type" => "BudgetWorkspace", "id" => workspace.id }
          )
        end

        counts = outcome.operation_run.result_counts
        Result.new(
          workspace: workspace.reload,
          operation_run: outcome.operation_run,
          comparison_count: counts.fetch("comparison_count"),
          smoke_read_count: counts.fetch("smoke_read_count"),
          flags_restored: flags_restored?
        )
      end

      private

      attr_reader :read_window, :rehearsal_id, :user, :workspace

      def run_smoke_reads!
        workspace.reload
        user.reload
        user.accounts.reset
        reads = [
          -> { Overview::PageData.new(user: user).call },
          -> { Reports::OverviewQuery.call(user: user) },
          -> { Accounts::Summary.new(user: user, include_trend: true).call },
          -> { Activity::IndexQuery.call(user: user, view: "all") }
        ]
        first_account = user.accounts.active_first.first
        reads << -> { Accounts::DetailPage.new(account: first_account.reload).call } if first_account
        reads.each(&:call)
        reads.size
      end

      def flags_restored?
        read_window.restored?
      end

      GateFailed = Eligibility::GateFailed
    end
  end
end
