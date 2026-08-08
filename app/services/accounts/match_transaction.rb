module Accounts
  class MatchTransaction
    def self.call(workspace:, actor_membership:, transaction:, budget_item:, amount:, idempotency_key:, match_kind: "manual")
      new(
        workspace: workspace,
        actor_membership: actor_membership,
        transaction: transaction,
        budget_item: budget_item,
        amount: amount,
        idempotency_key: idempotency_key,
        match_kind: match_kind
      ).call
    end

    def initialize(workspace:, actor_membership:, transaction:, budget_item:, amount:, idempotency_key:, match_kind:)
      @workspace = workspace
      @actor_membership = actor_membership
      @transaction = transaction
      @budget_item = budget_item
      @amount = amount.to_d
      @idempotency_key = idempotency_key
      @match_kind = match_kind
    end

    def call
      Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: actor_membership)
      validate_scope!

      Platform::Operations::Executor.call(
        workspace: workspace,
        actor_membership: actor_membership,
        operation_type: "match_transaction",
        idempotency_key: idempotency_key,
        request: { transaction_id: transaction.id, budget_item_id: budget_item.id, amount: amount, match_kind: match_kind },
        redacted_parameters: { "field_names" => %w[amount budget_item_id financial_transaction_id match_kind] },
        on_replay: ->(reference) { BudgetAllocation.find(reference.fetch("id")) }
      ) do |operation|
        transaction.lock!
        budget_item.lock!
        validate_state!
        validate_available_amount!

        allocation = BudgetAllocation.create!(
          budget_workspace: workspace,
          budget_item: budget_item,
          financial_transaction: transaction,
          amount: amount,
          currency_code: workspace.default_currency_code,
          match_kind: match_kind,
          match_confidence: match_kind == "exact_import" ? 1 : nil,
          matched_by_membership: actor_membership,
          matched_at: Time.current
        )
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: actor_membership,
          operation_run: operation,
          entity: allocation,
          action: "match",
          changed_fields: %i[budget_item financial_transaction amount match_kind]
        )
        Platform::Operations::Executor::Completion.new(
          value: allocation,
          result_counts: { "allocations" => 1 },
          result_reference: { "type" => "BudgetAllocation", "id" => allocation.id }
        )
      end
    end

    private

    attr_reader :actor_membership, :amount, :budget_item, :idempotency_key,
      :match_kind, :transaction, :workspace

    def validate_scope!
      return if transaction.budget_workspace_id == workspace.id && budget_item.budget_workspace_id == workspace.id

      raise InvalidMatch, "transaction and budget item must belong to this workspace"
    end

    def validate_state!
      raise InvalidMatch, "only posted transactions can be matched" unless transaction.state_posted?
      raise InvalidMatch, "only open budget items can be matched" unless budget_item.state_open?
      unless budget_item.budget_period.state_open? || budget_item.budget_period.state_reopened?
        raise InvalidMatch, "Reopen the closed month before matching late activity to its plan."
      end
    end

    def validate_available_amount!
      raise InvalidMatch, "allocation amount must be positive" unless amount.positive?
      raise InvalidMatch, "allocation exceeds the transaction amount available" if amount > transaction.available_to_allocate
    end

    class InvalidMatch < StandardError; end
  end
end
