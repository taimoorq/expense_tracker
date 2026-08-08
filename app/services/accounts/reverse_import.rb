module Accounts
  class ReverseImport
    def self.call(workspace:, actor_membership:, import_batch:, idempotency_key:)
      new(
        workspace: workspace,
        actor_membership: actor_membership,
        import_batch: import_batch,
        idempotency_key: idempotency_key
      ).call
    end

    def initialize(workspace:, actor_membership:, import_batch:, idempotency_key:)
      @workspace = workspace
      @actor_membership = actor_membership
      @import_batch = import_batch
      @idempotency_key = idempotency_key
    end

    def call
      Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: actor_membership)
      raise ArgumentError, "import batch must belong to this workspace" unless import_batch.budget_workspace_id == workspace.id

      Platform::Operations::Executor.call(
        workspace: workspace,
        actor_membership: actor_membership,
        operation_type: "reverse_import_batch",
        idempotency_key: idempotency_key,
        request: { import_batch_id: import_batch.id },
        redacted_parameters: { "import_batch_id" => import_batch.id },
        retryable: true,
        on_replay: ->(reference) { ImportBatch.find(reference.fetch("id")) }
      ) do |operation|
        import_batch.lock!
        raise InvalidState, "only committed imports can be reversed" unless import_batch.status_committed?

        import_batch.update!(status: "reverting")
        transactions = FinancialTransaction.where(import_row_id: import_batch.import_rows.select(:id))
        transaction_count = transactions.where.not(state: "reversed").update_all(state: "reversed", updated_at: Time.current)
        row_count = import_batch.import_rows.where.not(status: "reversed").update_all(status: "reversed", updated_at: Time.current)
        observation_count = import_batch.balance_observations
          .where.not(status: "superseded")
          .update_all(status: "superseded", updated_at: Time.current)
        import_batch.update!(status: "reverted", reverted_at: Time.current)
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: actor_membership,
          operation_run: operation,
          entity: import_batch,
          action: "import_reversal",
          changed_fields: %i[status reverted_at import_rows financial_transactions balance_observations]
        )
        Platform::Operations::Executor::Completion.new(
          value: import_batch,
          result_counts: {
            "import_rows_reversed" => row_count,
            "transactions_reversed" => transaction_count,
            "observations_superseded" => observation_count
          },
          result_reference: { "type" => "ImportBatch", "id" => import_batch.id }
        )
      end
    end

    private

    attr_reader :actor_membership, :idempotency_key, :import_batch, :workspace

    class InvalidState < StandardError; end
  end
end
