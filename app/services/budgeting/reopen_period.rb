module Budgeting
  class ReopenPeriod
    def self.call(workspace:, actor_membership:, budget_period:, idempotency_key:)
      new(
        workspace: workspace,
        actor_membership: actor_membership,
        budget_period: budget_period,
        idempotency_key: idempotency_key
      ).call
    end

    def initialize(workspace:, actor_membership:, budget_period:, idempotency_key:)
      @workspace = workspace
      @actor_membership = actor_membership
      @budget_period = budget_period
      @idempotency_key = idempotency_key
    end

    def call
      Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: actor_membership)
      raise ClosePeriod::InvalidState, "budget period must belong to this workspace" unless budget_period.budget_workspace_id == workspace.id

      Platform::Operations::Executor.call(
        workspace: workspace,
        actor_membership: actor_membership,
        operation_type: "reopen_budget_period",
        idempotency_key: idempotency_key,
        request: { budget_period_id: budget_period.id },
        redacted_parameters: { "field_names" => [ "budget_period_id" ] },
        retryable: true,
        on_replay: ->(reference) { BudgetPeriod.find(reference.fetch("id")) }
      ) do |operation|
        budget_period.lock!
        raise ClosePeriod::InvalidState, "only a closed period can be reopened" unless budget_period.state_closed?

        close = budget_period.month_closes.state_closed.lock.sole
        close.update!(state: "superseded")
        budget_period.update!(state: "reopened")
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: actor_membership,
          operation_run: operation,
          entity: budget_period,
          action: "reopen",
          changed_fields: %i[state]
        )
        Platform::Operations::Executor::Completion.new(
          value: budget_period,
          result_counts: { "month_closes_superseded" => 1 },
          result_reference: { "type" => "BudgetPeriod", "id" => budget_period.id }
        )
      end
    end

    private

    attr_reader :actor_membership, :budget_period, :idempotency_key, :workspace
  end
end
