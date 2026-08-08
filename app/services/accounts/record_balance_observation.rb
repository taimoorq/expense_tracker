module Accounts
  class RecordBalanceObservation
    def self.call(workspace:, actor_membership:, account:, idempotency_key:, attributes:)
      new(
        workspace: workspace,
        actor_membership: actor_membership,
        account: account,
        idempotency_key: idempotency_key,
        attributes: attributes
      ).call
    end

    def initialize(workspace:, actor_membership:, account:, idempotency_key:, attributes:)
      @workspace = workspace
      @actor_membership = actor_membership
      @account = account
      @idempotency_key = idempotency_key
      @attributes = attributes.to_h.symbolize_keys
    end

    def call
      Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: actor_membership)
      raise ArgumentError, "account must belong to this workspace" unless account.budget_workspace_id == workspace.id

      Platform::Operations::Executor.call(
        workspace: workspace,
        actor_membership: actor_membership,
        operation_type: "record_balance_observation",
        idempotency_key: idempotency_key,
        request: attributes.merge(account_id: account.id),
        redacted_parameters: { "field_names" => attributes.keys.map(&:to_s).sort },
        on_replay: ->(reference) { BalanceObservation.find(reference.fetch("id")) }
      ) do |operation|
        observation = BalanceObservation.create!(
          attributes.merge(
            budget_workspace: workspace,
            account: account,
            actor_membership: actor_membership,
            currency_code: workspace.default_currency_code,
            source_kind: attributes.fetch(:source_kind, "manual"),
            status: attributes.fetch(:status, "trusted")
          )
        )
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: actor_membership,
          operation_run: operation,
          entity: observation,
          action: "trust_observation",
          changed_fields: attributes.keys
        )
        Platform::Operations::Executor::Completion.new(
          value: observation,
          result_counts: { "balance_observations" => 1 },
          result_reference: { "type" => "BalanceObservation", "id" => observation.id }
        )
      end
    end

    private

    attr_reader :account, :actor_membership, :attributes, :idempotency_key, :workspace
  end
end
