module Platform
  module TargetSync
    class AccountActivityImportWriter
      MAPPING_VERSION = "target-live-v1".freeze

      def self.call(legacy_import:, operation_run: nil)
        new(legacy_import: legacy_import, operation_run: operation_run).call
      end

      def initialize(legacy_import:, operation_run: nil)
        @legacy_import = legacy_import
        @operation_run = operation_run
      end

      def call
        @context = Context.for(legacy_import)
        return if context.blank?
        return sync(operation_run) if operation_run

        Platform::Operations::Executor.call(
          workspace: workspace,
          actor_membership: membership,
          operation_type: "commit_legacy_account_activity_import",
          idempotency_key: legacy_import.commit_idempotency_key,
          request: request_identity,
          redacted_parameters: {
            "legacy_record_type" => "AccountActivityImport",
            "legacy_record_id" => legacy_import.id,
            "row_count" => legacy_import.rows_count
          },
          retryable: true,
          on_replay: ->(reference) { ImportBatch.find(reference.fetch("id")) }
        ) { |operation| sync(operation) }
      end

      private

      attr_reader :context, :legacy_import, :mapping_store, :operation_run

      delegate :membership, :workspace, to: :context

      def sync(operation)
        unless operation.budget_workspace_id == workspace.id
          raise WriteRejected, "The import operation belongs to another workspace"
        end

        @mapping_store = TargetBackfill::MappingStore.new(
          workspace: workspace,
          operation_run: operation,
          version: MAPPING_VERSION
        )
        batch = sync_batch(operation)
        sync_balance_observation(batch)
        counts = sync_rows(batch)
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: membership,
          operation_run: operation,
          entity: batch,
          action: "import",
          changed_fields: %i[row_count imported_count duplicate_count coverage_starts_on coverage_ends_on]
        )
        Platform::Operations::Executor::Completion.new(
          value: batch,
          result_counts: counts.merge("import_batches" => 1),
          result_reference: { "type" => "ImportBatch", "id" => batch.id }
        )
      end

      def sync_batch(operation)
        batch = mapping_store.target_for(source: legacy_import, target_class: ImportBatch) ||
          mapping_store.build_target(source: legacy_import, target_class: ImportBatch)
        batch.assign_attributes(
          budget_workspace: workspace,
          account: legacy_import.account,
          operation_run: operation,
          actor_membership: membership,
          import_kind: "account_activity",
          original_filename: legacy_import.original_filename,
          file_digest: legacy_import.file_digest,
          idempotency_key: legacy_import.commit_idempotency_key,
          parser_version: "legacy-csv-v1",
          mapping_version: MAPPING_VERSION,
          fingerprint_version: "legacy-v1",
          coverage_starts_on: legacy_import.started_on,
          coverage_ends_on: legacy_import.ended_on,
          status: "committed",
          row_count: legacy_import.rows_count,
          imported_count: legacy_import.imported_count,
          duplicate_count: legacy_import.duplicate_count,
          error_count: error_count,
          redacted_metadata: { "legacy_import_id" => legacy_import.id },
          warnings: legacy_import.warning_messages,
          committed_at: legacy_import.created_at
        )
        batch.save!
        mapping_store.record!(source: legacy_import, target: batch, source_attributes: import_source_attributes)
        batch
      end

      def sync_balance_observation(batch)
        return unless legacy_import.institution_balance? && legacy_import.institution_balance_as_of.present?

        observation = mapping_store.target_for(source: legacy_import, target_class: BalanceObservation) ||
          mapping_store.build_target(source: legacy_import, target_class: BalanceObservation)
        effective_at = legacy_import.institution_balance_as_of.end_of_day
        observation.assign_attributes(
          budget_workspace: workspace,
          account: legacy_import.account,
          observed_at: [ Time.current, effective_at ].max,
          effective_through_at: effective_at,
          balance: legacy_import.institution_balance,
          currency_code: workspace.default_currency_code,
          source_kind: "institution_file",
          source_import_batch: batch,
          actor_membership: membership,
          status: "trusted",
          notes: "Institution balance from account activity import"
        )
        observation.save!
        mapping_store.record!(
          source: legacy_import,
          target: observation,
          source_attributes: {
            institution_balance: legacy_import.institution_balance.to_s("F"),
            institution_balance_as_of: legacy_import.institution_balance_as_of
          },
          metadata: { "effective_through_convention" => "calendar_day_end" }
        )
      end

      def sync_rows(batch)
        counts = Hash.new(0)
        legacy_import.account_activities.find_each(batch_size: 1_000) do |activity|
          sync_row(activity, batch, counts)
        end
        counts
      end

      def sync_row(activity, batch, counts)
        row = mapping_store.target_for(source: activity, target_class: ImportRow) ||
          mapping_store.build_target(source: activity, target_class: ImportRow)
        row.assign_attributes(
          budget_workspace: workspace,
          import_batch: batch,
          row_number: activity.row_number,
          fingerprint: activity.fingerprint,
          fingerprint_version: "legacy-v1",
          raw_payload: activity.raw_payload,
          normalized_payload: normalized_payload(activity),
          normalization_result: "normalized",
          status: "accepted"
        )
        row.save!

        transaction = sync_transaction(activity, row, counts)
        row.update!(financial_transaction: transaction)
        mapping_store.record!(source: activity, target: row, source_attributes: activity_source_attributes(activity))
        mapping_store.record!(source: activity, target: transaction, source_attributes: activity_source_attributes(activity))
        counts["import_rows"] += 1
        counts["financial_transactions"] += 1
      end

      def sync_transaction(activity, row, counts)
        transaction = mapping_store.target_for(source: activity, target_class: FinancialTransaction) ||
          mapping_store.build_target(source: activity, target_class: FinancialTransaction)
        transaction.assign_attributes(
          budget_workspace: workspace,
          effective_on: activity.transaction_on,
          posted_on: activity.posted_on,
          description: activity.description,
          memo: activity.memo,
          gross_amount: activity.amount,
          currency_code: workspace.default_currency_code,
          flow_kind: activity.account_delta.positive? ? "income" : "outflow",
          state: "posted",
          origin_kind: "institution_import",
          import_row: row,
          idempotency_key: "legacy:account-activity:#{activity.id}"
        )
        transaction.save!
        posting = transaction.account_postings.find_or_initialize_by(sequence_number: 0)
        posting.assign_attributes(
          budget_workspace: workspace,
          account: activity.account,
          amount: activity.account_delta,
          currency_code: workspace.default_currency_code,
          role: "primary"
        )
        posting.save!
        counts["account_postings"] += 1
        transaction
      end

      def normalized_payload(activity)
        {
          "transaction_on" => activity.transaction_on,
          "posted_on" => activity.posted_on,
          "description" => activity.description,
          "category" => activity.category,
          "activity_type" => activity.activity_type,
          "amount" => activity.amount.to_s("F"),
          "account_delta" => activity.account_delta.to_s("F")
        }.compact
      end

      def import_source_attributes
        legacy_import.attributes.except("metadata", "created_at", "updated_at", "lock_version")
      end

      def activity_source_attributes(activity)
        activity.attributes.except("raw_payload", "created_at", "updated_at")
      end

      def request_identity
        {
          legacy_import_id: legacy_import.id,
          account_id: legacy_import.account_id,
          file_digest: legacy_import.file_digest,
          rows_count: legacy_import.rows_count,
          imported_count: legacy_import.imported_count,
          duplicate_count: legacy_import.duplicate_count
        }
      end

      def error_count
        legacy_import.rows_count - legacy_import.imported_count - legacy_import.duplicate_count
      end
    end
  end
end
