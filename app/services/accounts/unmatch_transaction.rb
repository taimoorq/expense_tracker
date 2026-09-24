module Accounts
  class UnmatchTransaction
    def self.call(workspace:, actor_membership:, allocation:, idempotency_key:)
      new(
        workspace: workspace,
        actor_membership: actor_membership,
        allocation: allocation,
        idempotency_key: idempotency_key
      ).call
    end

    def initialize(workspace:, actor_membership:, allocation:, idempotency_key:)
      @workspace = workspace
      @actor_membership = actor_membership
      @allocation = allocation
      @idempotency_key = idempotency_key
    end

    def call
      Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: actor_membership)
      raise ArgumentError, "allocation must belong to this workspace" unless allocation.budget_workspace_id == workspace.id

      budget_item = allocation.budget_item
      Platform::Operations::Executor.call(
        workspace: workspace,
        actor_membership: actor_membership,
        operation_type: "unmatch_transaction",
        idempotency_key: idempotency_key,
        request: { allocation_id: allocation.id },
        redacted_parameters: { "field_names" => [ "allocation_id" ] },
        on_replay: ->(reference) { BudgetItem.find(reference.fetch("id")) }
      ) do |operation|
        workspace.lock!
        allocation.lock!
        validate_open_periods!(budget_item)
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: actor_membership,
          operation_run: operation,
          entity: allocation,
          action: "unmatch",
          changed_fields: %i[budget_item financial_transaction amount]
        )
        allocation.destroy!
        Platform::Operations::Executor::Completion.new(
          value: budget_item,
          result_counts: { "allocations_removed" => 1 },
          result_reference: { "type" => "BudgetItem", "id" => budget_item.id }
        )
      end
    end

    private

    attr_reader :actor_membership, :allocation, :idempotency_key, :workspace

    def validate_open_periods!(budget_item)
      OpenPeriodGuard.call(workspace: workspace, dates: [ allocation.financial_transaction.effective_on, budget_item.budget_period.starts_on ])
    rescue ArgumentError => error
      raise InvalidMatch, error.message
    end

    class InvalidMatch < StandardError; end
  end
end
