module Budgeting
  class CreateBudgetItem
    def self.call(workspace:, actor_membership:, budget_period:, idempotency_key:, attributes:)
      new(
        workspace: workspace,
        actor_membership: actor_membership,
        budget_period: budget_period,
        idempotency_key: idempotency_key,
        attributes: attributes
      ).call
    end

    def initialize(workspace:, actor_membership:, budget_period:, idempotency_key:, attributes:)
      @workspace = workspace
      @actor_membership = actor_membership
      @budget_period = budget_period
      @idempotency_key = idempotency_key
      @attributes = attributes.to_h.symbolize_keys
    end

    def call
      Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: actor_membership)
      raise ArgumentError, "budget period must be open in this workspace" unless valid_period?

      Platform::Operations::Executor.call(
        workspace: workspace,
        actor_membership: actor_membership,
        operation_type: "create_budget_item",
        idempotency_key: idempotency_key,
        request: request_identity,
        redacted_parameters: { "field_names" => attributes.keys.map(&:to_s).sort },
        on_replay: ->(reference) { BudgetItem.find(reference.fetch("id")) }
      ) do |operation|
        item = BudgetItem.create!(
          attributes.merge(
            budget_workspace: workspace,
            budget_period: budget_period,
            currency_code: workspace.default_currency_code,
            origin_kind: attributes.fetch(:origin_kind, "manual")
          )
        )
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: actor_membership,
          operation_run: operation,
          entity: item,
          action: "create",
          changed_fields: attributes.keys
        )
        Platform::Operations::Executor::Completion.new(
          value: item,
          result_counts: { "budget_items" => 1 },
          result_reference: { "type" => "BudgetItem", "id" => item.id }
        )
      end
    end

    private

    attr_reader :actor_membership, :attributes, :budget_period, :idempotency_key, :workspace

    def valid_period?
      budget_period.budget_workspace_id == workspace.id && budget_period.state_open?
    end

    def request_identity
      attributes.transform_values { |value| value.respond_to?(:id) ? value.id : value }
        .merge(budget_period_id: budget_period.id)
    end
  end
end
