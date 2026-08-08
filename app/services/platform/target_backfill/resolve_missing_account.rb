module Platform
  module TargetBackfill
    class ResolveMissingAccount
      ERROR_CODE = "paid_entry_missing_account".freeze

      def self.call(workspace:, actor_membership:, discrepancy:, account:)
        new(
          workspace: workspace,
          actor_membership: actor_membership,
          discrepancy: discrepancy,
          account: account
        ).call
      end

      def initialize(workspace:, actor_membership:, discrepancy:, account:)
        @workspace = workspace
        @actor_membership = actor_membership
        @discrepancy = discrepancy
        @account = account
      end

      def call
        Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: actor_membership)
        validate_scope!

        Platform::Operations::Executor.call(
          workspace: workspace,
          actor_membership: actor_membership,
          operation_type: "resolve_migration_missing_account",
          idempotency_key: "#{discrepancy.id}:#{account.id}",
          request: { discrepancy_id: discrepancy.id, account_id: account.id },
          redacted_parameters: { "field_names" => [ "discrepancy_id", "account_id" ] },
          retryable: true,
          on_replay: ->(reference) { MigrationDiscrepancy.find(reference.fetch("id")) }
        ) do |operation|
          discrepancy.lock!
          raise InvalidState, "This review item has already been resolved." unless discrepancy.status_open?

          entry = legacy_entry
          transaction = mapped_target!(entry, FinancialTransaction)
          assign_account!(entry, transaction)
          create_posting!(transaction)
          discrepancy.update!(status: "resolved", resolved_at: Time.current, operation_run: operation)
          verification = verify_backfill!(operation)
          record_audit!(operation)

          Platform::Operations::Executor::Completion.new(
            value: discrepancy,
            result_counts: {
              "migration_discrepancies_resolved" => 1,
              "account_postings_created" => 1,
              "workspace_clean" => verification.clean? ? 1 : 0
            },
            result_reference: { "type" => "MigrationDiscrepancy", "id" => discrepancy.id }
          )
        end
      end

      private

      attr_reader :account, :actor_membership, :discrepancy, :workspace

      def validate_scope!
        unless discrepancy.budget_workspace_id == workspace.id &&
            discrepancy.legacy_record_type == "ExpenseEntry" &&
            discrepancy.code == ERROR_CODE
          raise InvalidState, "This review item cannot be resolved with an account assignment."
        end
        unless account.user_id == actor_membership.user_id && account.budget_workspace_id == workspace.id
          raise Identity::WorkspaceAccess::NotAuthorized, "The selected account is outside this budget."
        end
      end

      def legacy_entry
        actor_membership.user.expense_entries.find(discrepancy.legacy_record_id)
      end

      def mapped_target!(source, target_class)
        mapping = workspace.legacy_record_mappings.find_by!(
          legacy_record_type: source.class.name,
          legacy_record_id: source.id,
          target_record_type: target_class.name
        )
        target_class.find(mapping.target_record_id)
      end

      def assign_account!(entry, transaction)
        unless transaction.flow_kind_income? || transaction.flow_kind_outflow?
          raise InvalidState, "Transfers need both accounts and cannot be repaired from this one-account review."
        end
        raise InvalidState, "This entry already has account context." if entry.source_account_id.present? || entry.destination_account_id.present?

        entry.update!(source_account: account)
      end

      def create_posting!(transaction)
        raise InvalidState, "This transaction already has an account posting." if transaction.account_postings.exists?

        signed_amount = transaction.flow_kind_income? ? transaction.gross_amount : -transaction.gross_amount
        transaction.account_postings.create!(
          budget_workspace: workspace,
          account: account,
          amount: signed_amount,
          currency_code: workspace.default_currency_code,
          role: "primary",
          sequence_number: 0
        )
      end

      def verify_backfill!(operation)
        verification = Verifier.call(
          user: actor_membership.user,
          workspace: workspace,
          operation_run: operation
        )
        finalize_backfill! if verification.clean?
        verification
      end

      def finalize_backfill!
        workspace.update!(
          target_backfill_version: WorkspaceBootstrap::VERSION,
          target_backfilled_at: Time.current
        )
        backfill_operation = workspace.operation_runs.find_by(
          operation_type: "target_model_backfill",
          idempotency_key: WorkspaceBootstrap::VERSION
        )
        return if backfill_operation.blank?

        backfill_operation.update!(
          state: "succeeded",
          result_counts: backfill_operation.result_counts.merge("verification" => { "clean" => true }),
          completed_at: Time.current,
          error_code: nil
        )
      end

      def record_audit!(operation)
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: actor_membership,
          operation_run: operation,
          entity: discrepancy,
          action: "resolve_migration_discrepancy",
          changed_fields: %i[status resolved_at account_id account_posting]
        )
      end

      class InvalidState < StandardError; end
    end
  end
end
