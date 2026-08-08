module Budgeting
  class FulfillItem
    def self.call(workspace:, actor_membership:, budget_item:, idempotency_key:, transaction_attributes:)
      new(
        workspace: workspace,
        actor_membership: actor_membership,
        budget_item: budget_item,
        idempotency_key: idempotency_key,
        transaction_attributes: transaction_attributes
      ).call
    end

    def initialize(workspace:, actor_membership:, budget_item:, idempotency_key:, transaction_attributes:)
      @workspace = workspace
      @actor_membership = actor_membership
      @budget_item = budget_item
      @idempotency_key = idempotency_key
      @transaction_attributes = transaction_attributes.to_h.symbolize_keys
    end

    def call
      Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: actor_membership)
      raise ArgumentError, "budget item must belong to this workspace" unless budget_item.budget_workspace_id == workspace.id

      Platform::Operations::Executor.call(
        workspace: workspace,
        actor_membership: actor_membership,
        operation_type: "fulfill_budget_item",
        idempotency_key: idempotency_key,
        request: request_identity,
        redacted_parameters: { "field_names" => transaction_attributes.keys.map(&:to_s).sort },
        on_replay: ->(reference) { FinancialTransaction.find(reference.fetch("id")) }
      ) do |operation|
        budget_item.lock!
        raise InvalidState, "only open budget items can be fulfilled" unless budget_item.state_open?

        transaction = Accounts::TransactionBuilder.new(
          workspace: workspace,
          attributes: normalized_transaction_attributes(operation)
        ).call
        allocation = transaction.budget_allocations.create!(
          budget_workspace: workspace,
          budget_item: budget_item,
          amount: transaction.gross_amount,
          currency_code: workspace.default_currency_code,
          match_kind: "manual",
          matched_by_membership: actor_membership,
          matched_at: Time.current
        )
        record_audit(operation, transaction, allocation)
        Platform::Operations::Executor::Completion.new(
          value: transaction,
          result_counts: {
            "transactions" => 1,
            "postings" => transaction.account_postings.size,
            "allocations" => 1
          },
          result_reference: { "type" => "FinancialTransaction", "id" => transaction.id }
        )
      end
    end

    private

    attr_reader :actor_membership, :budget_item, :idempotency_key, :transaction_attributes, :workspace

    def normalized_transaction_attributes(operation)
      transaction_attributes.merge(
        amount: transaction_attributes.fetch(:amount, budget_item.remaining_amount),
        effective_on: transaction_attributes.fetch(:effective_on, budget_item.scheduled_on || Date.current),
        description: transaction_attributes.fetch(:description, budget_item.payee_snapshot.presence || budget_item.name_snapshot.presence || "Budget item actual"),
        category: budget_item.category,
        flow_kind: budget_item.flow_kind,
        idempotency_key: "operation:#{operation.id}"
      )
    end

    def record_audit(operation, transaction, allocation)
      Audit::Recorder.call(
        workspace: workspace,
        actor_membership: actor_membership,
        operation_run: operation,
        entity: transaction,
        action: "create",
        changed_fields: %i[effective_on gross_amount flow_kind account_postings]
      )
      Audit::Recorder.call(
        workspace: workspace,
        actor_membership: actor_membership,
        operation_run: operation,
        entity: allocation,
        action: "match",
        changed_fields: %i[budget_item financial_transaction amount]
      )
    end

    def request_identity
      transaction_attributes.transform_values { |value| value.respond_to?(:id) ? value.id : value }
        .merge(budget_item_id: budget_item.id)
    end

    class InvalidState < StandardError; end
  end
end
