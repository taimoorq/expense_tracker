module Accounts
  class RecordManualTransaction
    def self.call(workspace:, actor_membership:, idempotency_key:, attributes:)
      new(
        workspace: workspace,
        actor_membership: actor_membership,
        idempotency_key: idempotency_key,
        attributes: attributes
      ).call
    end

    def initialize(workspace:, actor_membership:, idempotency_key:, attributes:)
      @workspace = workspace
      @actor_membership = actor_membership
      @idempotency_key = idempotency_key
      @attributes = attributes.to_h.symbolize_keys
    end

    def call
      Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: actor_membership)
      Platform::Operations::Executor.call(
        workspace: workspace,
        actor_membership: actor_membership,
        operation_type: "record_manual_transaction",
        idempotency_key: idempotency_key,
        request: request_identity,
        redacted_parameters: { "field_names" => attributes.keys.map(&:to_s).sort },
        on_replay: ->(reference) { FinancialTransaction.find(reference.fetch("id")) }
      ) do |operation|
        transaction = TransactionBuilder.new(
          workspace: workspace,
          attributes: attributes.merge(idempotency_key: "operation:#{operation.id}")
        ).call
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: actor_membership,
          operation_run: operation,
          entity: transaction,
          action: "create",
          changed_fields: %i[effective_on description gross_amount flow_kind account_postings]
        )
        Platform::Operations::Executor::Completion.new(
          value: transaction,
          result_counts: { "transactions" => 1, "postings" => transaction.account_postings.size },
          result_reference: { "type" => "FinancialTransaction", "id" => transaction.id }
        )
      end
    end

    private

    attr_reader :actor_membership, :attributes, :idempotency_key, :workspace

    def request_identity
      attributes.transform_values { |value| value.respond_to?(:id) ? value.id : value }
    end
  end
end
