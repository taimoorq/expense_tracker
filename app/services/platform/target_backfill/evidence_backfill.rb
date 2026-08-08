require "digest"

module Platform
  module TargetBackfill
    class EvidenceBackfill
      Result = Data.define(:workspace, :operation_run, :counts) do
        def as_json(*)
          { workspace_id: workspace.id, operation_run_id: operation_run.id, counts: counts }
        end
      end

      def self.call(user:)
        new(user: user).call
      end

      def initialize(user:)
        @user = user
      end

      def call
        planning = PlanningBackfill.call(user: user)
        @workspace = planning.workspace
        @operation_run = planning.operation_run
        @membership = workspace.workspace_memberships.find_by!(user: user)
        @mapping_store = MappingStore.new(workspace: workspace, operation_run: operation_run)
        @counts = Hash.new(0)

        backfill_snapshots
        backfill_imports
        backfill_paid_entries
        persist_counts

        Result.new(workspace: workspace, operation_run: operation_run, counts: counts)
      end

      private

      attr_reader :counts, :mapping_store, :membership, :operation_run, :user, :workspace

      def backfill_snapshots
        user.account_snapshots.includes(:account).find_each do |snapshot|
          ApplicationRecord.transaction do
            observation = mapping_store.target_for(source: snapshot, target_class: BalanceObservation) ||
              mapping_store.build_target(source: snapshot, target_class: BalanceObservation)
            effective_at = snapshot.recorded_on.end_of_day
            observation.assign_attributes(
              budget_workspace: workspace,
              account: snapshot.account,
              observed_at: [ snapshot.created_at, effective_at ].max,
              effective_through_at: effective_at,
              balance: snapshot.balance,
              available_balance: snapshot.available_balance,
              currency_code: currency_code,
              source_kind: "migration",
              actor_membership: membership,
              status: "trusted",
              notes: snapshot.notes
            )
            observation.save!
            mapping_store.record!(
              source: snapshot,
              target: observation,
              source_attributes: snapshot.attributes.except("created_at", "updated_at", "lock_version"),
              metadata: { "effective_through_convention" => "calendar_day_end" }
            )
            counts["balance_observations"] += 1
          end
        end
      end

      def backfill_imports
        user.account_activity_imports.includes(:account).find_each do |legacy_import|
          ApplicationRecord.transaction do
            import_batch = backfill_import_batch(legacy_import)
            backfill_import_balance(legacy_import, import_batch)
          end
          legacy_import.account_activities.find_each do |activity|
            backfill_activity(activity, import_batch_for(legacy_import))
          end
        end
      end

      def backfill_import_batch(legacy_import)
        import_batch = mapping_store.target_for(source: legacy_import, target_class: ImportBatch) ||
          mapping_store.build_target(source: legacy_import, target_class: ImportBatch)
        import_batch.assign_attributes(
          budget_workspace: workspace,
          account: legacy_import.account,
          operation_run: operation_run,
          actor_membership: membership,
          import_kind: "account_activity",
          original_filename: legacy_import.original_filename,
          file_digest: legacy_import.file_digest || legacy_digest("AccountActivityImport", legacy_import.id),
          idempotency_key: legacy_import.commit_idempotency_key || "migration:account-activity-import:#{legacy_import.id}",
          parser_version: "legacy-csv-v1",
          mapping_version: "legacy-v1",
          fingerprint_version: "legacy-v1",
          coverage_starts_on: legacy_import.started_on,
          coverage_ends_on: legacy_import.ended_on,
          status: "committed",
          row_count: legacy_import.rows_count,
          imported_count: legacy_import.imported_count,
          duplicate_count: legacy_import.duplicate_count,
          error_count: legacy_import.rows_count - legacy_import.imported_count - legacy_import.duplicate_count,
          redacted_metadata: { "legacy_import_id" => legacy_import.id, "institution_name" => legacy_import.institution_name }.compact,
          warnings: legacy_import.warning_messages,
          committed_at: legacy_import.created_at
        )
        import_batch.save!
        mapping_store.record!(
          source: legacy_import,
          target: import_batch,
          source_attributes: legacy_import.attributes.except("metadata", "created_at", "updated_at", "lock_version")
        )
        counts["import_batches"] += 1
        import_batch
      end

      def backfill_import_balance(legacy_import, import_batch)
        return unless legacy_import.institution_balance? && legacy_import.institution_balance_as_of.present?

        observation = mapping_store.target_for(source: legacy_import, target_class: BalanceObservation) ||
          BalanceObservation.new
        effective_at = legacy_import.institution_balance_as_of.end_of_day
        observation.assign_attributes(
          budget_workspace: workspace,
          account: legacy_import.account,
          observed_at: [ legacy_import.created_at, effective_at ].max,
          effective_through_at: effective_at,
          balance: legacy_import.institution_balance,
          currency_code: currency_code,
          source_kind: "institution_file",
          source_import_batch: import_batch,
          status: "trusted",
          notes: "Migrated institution balance"
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
        counts["balance_observations"] += 1
      end

      def backfill_activity(activity, import_batch)
        ApplicationRecord.transaction do
          import_row = mapping_store.target_for(source: activity, target_class: ImportRow) ||
            mapping_store.build_target(source: activity, target_class: ImportRow)
          import_row.assign_attributes(import_row_attributes(activity, import_batch))
          import_row.save!

          transaction = backfill_activity_transaction(activity, import_row)
          import_row.update!(financial_transaction: transaction)
          mapping_store.record!(source: activity, target: import_row, source_attributes: activity_source_attributes(activity))
          mapping_store.record!(source: activity, target: transaction, source_attributes: activity_source_attributes(activity))
          counts["import_rows"] += 1
          counts["financial_transactions"] += 1
        end
      end

      def import_row_attributes(activity, import_batch)
        {
          budget_workspace: workspace,
          import_batch: import_batch,
          row_number: activity.row_number,
          fingerprint: activity.fingerprint,
          fingerprint_version: "legacy-v1",
          raw_payload: activity.raw_payload,
          normalized_payload: {
            "transaction_on" => activity.transaction_on,
            "posted_on" => activity.posted_on,
            "description" => activity.description,
            "category" => activity.category,
            "activity_type" => activity.activity_type,
            "amount" => activity.amount.to_s("F"),
            "account_delta" => activity.account_delta.to_s("F")
          }.compact,
          normalization_result: "normalized",
          status: "accepted"
        }
      end

      def backfill_activity_transaction(activity, import_row)
        transaction = mapping_store.target_for(source: activity, target_class: FinancialTransaction) ||
          mapping_store.build_target(source: activity, target_class: FinancialTransaction)
        transaction.assign_attributes(
          budget_workspace: workspace,
          effective_on: activity.transaction_on,
          posted_on: activity.posted_on,
          description: activity.description,
          memo: activity.memo,
          gross_amount: activity.amount,
          currency_code: currency_code,
          flow_kind: activity_flow_kind(activity),
          state: "posted",
          origin_kind: "institution_import",
          import_row: import_row,
          idempotency_key: "migration:account-activity:#{activity.id}"
        )
        transaction.save!
        backfill_activity_posting(activity, transaction)
        transaction
      end

      def backfill_activity_posting(activity, transaction)
        if activity.account_delta.zero?
          mapping_store.record_discrepancy!(source: activity, code: "zero_account_delta")
          return
        end

        posting = transaction.account_postings.find_or_initialize_by(sequence_number: 0)
        posting.assign_attributes(
          budget_workspace: workspace,
          account: activity.account,
          amount: activity.account_delta,
          currency_code: currency_code,
          role: "primary"
        )
        posting.save!
        counts["account_postings"] += 1
      end

      def activity_flow_kind(activity)
        return "income" if activity.account_delta.positive?
        return "outflow" if activity.account_delta.negative?

        "adjustment"
      end

      def backfill_paid_entries
        user.expense_entries.paid.includes(:account_activities, :source_account, :destination_account).find_each do |entry|
          item = mapped_target!(entry, BudgetItem)
          linked_transactions = entry.account_activities.filter_map do |activity|
            mapping_store.target_for(source: activity, target_class: FinancialTransaction)
          end

          if linked_transactions.any?
            linked_transactions.each { |transaction| backfill_allocation(entry, item, transaction, "exact_import") }
          elsif covered_by_legacy_import?(entry)
            mapping_store.record_discrepancy!(source: entry, code: "paid_entry_unmatched_in_import_coverage")
            counts["unmatched_paid_entries"] += 1
          else
            transaction = backfill_synthetic_transaction(entry, item)
            backfill_allocation(entry, item, transaction, "migration") if transaction.gross_amount.positive?
          end
        end
      end

      def backfill_synthetic_transaction(entry, item)
        ApplicationRecord.transaction do
          transaction = mapping_store.target_for(source: entry, target_class: FinancialTransaction) ||
            mapping_store.build_target(source: entry, target_class: FinancialTransaction)
          transaction.assign_attributes(
            budget_workspace: workspace,
            effective_on: entry.occurred_on || entry.budget_month.month_on,
            description: entry.payee.presence || entry.category.presence || "Migrated actual",
            payee: entry.payee,
            memo: entry.notes,
            category: item.category,
            gross_amount: entry.effective_amount,
            currency_code: currency_code,
            flow_kind: item_flow_kind(entry),
            state: "posted",
            origin_kind: "migration",
            idempotency_key: "migration:expense-entry:#{entry.id}"
          )
          transaction.save!
          backfill_entry_postings(entry, transaction)
          mapping_store.record!(
            source: entry,
            target: transaction,
            source_attributes: entry.attributes.except("created_at", "updated_at", "lock_version")
          )
          counts["financial_transactions"] += 1
          transaction
        end
      end

      def backfill_entry_postings(entry, transaction)
        amount = transaction.gross_amount
        return mapping_store.record_discrepancy!(source: entry, code: "zero_paid_entry") unless amount.positive?

        posting_values = if transaction.flow_kind_transfer?
          [ [ entry.source_account, -amount, "source" ], [ entry.destination_account, amount, "destination" ] ]
        elsif transaction.flow_kind_income?
          [ [ entry.source_account || entry.destination_account, amount, "primary" ] ]
        else
          [ [ entry.source_account, -amount, "primary" ] ]
        end

        missing_account = posting_values.any? { |account, _amount, _role| account.blank? }
        if missing_account
          mapping_store.record_discrepancy!(source: entry, code: "paid_entry_missing_account")
          return
        end

        posting_values.each_with_index do |(account, signed_amount, role), sequence_number|
          posting = transaction.account_postings.find_or_initialize_by(sequence_number: sequence_number)
          posting.assign_attributes(
            budget_workspace: workspace,
            account: account,
            amount: signed_amount,
            currency_code: currency_code,
            role: role
          )
          posting.save!
          counts["account_postings"] += 1
        end
      end

      def backfill_allocation(entry, item, transaction, match_kind)
        return unless transaction.gross_amount.positive?

        ApplicationRecord.transaction do
          allocation = BudgetAllocation.find_or_initialize_by(
            budget_item: item,
            financial_transaction: transaction
          )
          allocation.assign_attributes(
            budget_workspace: workspace,
            amount: transaction.gross_amount,
            currency_code: currency_code,
            match_kind: match_kind,
            match_confidence: match_kind == "exact_import" ? 1 : nil,
            matched_by_membership: membership,
            matched_at: transaction.created_at || Time.current
          )
          allocation.save!
          counts["budget_allocations"] += 1
        end
      rescue ActiveRecord::RecordInvalid => error
        mapping_store.record_discrepancy!(
          source: entry,
          code: "allocation_failed",
          details: { error_class: error.class.name }
        )
        raise
      end

      def item_flow_kind(entry)
        return "income" if entry.income?
        return "transfer" if entry.source_account_id.present? && entry.destination_account_id.present?

        "outflow"
      end

      def covered_by_legacy_import?(entry)
        account = entry.source_account || entry.destination_account
        return false if account.blank? || entry.occurred_on.blank?

        account.account_activity_imports
          .where(started_on: ..entry.occurred_on)
          .where(ended_on: entry.occurred_on..)
          .exists?
      end

      def import_batch_for(legacy_import)
        mapped_target!(legacy_import, ImportBatch)
      end

      def mapped_target!(source, target_class)
        mapping_store.target_for(source: source, target_class: target_class) ||
          raise(MappingStore::MappingConflict, "Missing #{target_class.name} mapping for #{source.class.name} #{source.id}")
      end

      def activity_source_attributes(activity)
        activity.attributes.except("raw_payload", "created_at", "updated_at")
      end

      def legacy_digest(type, id)
        Digest::SHA256.hexdigest([ WorkspaceBootstrap::VERSION, type, id ].join(":"))
      end

      def currency_code
        workspace.default_currency_code
      end

      def persist_counts
        operation_run.update!(result_counts: operation_run.result_counts.merge("evidence_backfill" => counts))
      end
    end
  end
end
