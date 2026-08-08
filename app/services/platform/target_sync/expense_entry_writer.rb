module Platform
  module TargetSync
    class ExpenseEntryWriter
      MAPPING_VERSION = "target-live-v1".freeze

      def self.call(entry:)
        new(entry: entry).call
      end

      def initialize(entry:)
        @entry = entry
      end

      def call
        @context = Context.for(entry)
        return if context.blank?

        Platform::Operations::Executor.call(
          workspace: workspace,
          actor_membership: membership,
          operation_type: "sync_legacy_expense_entry",
          idempotency_key: "legacy:ExpenseEntry:#{entry.id}:#{entry.lock_version}",
          request: source_attributes,
          redacted_parameters: { "legacy_record_type" => "ExpenseEntry", "legacy_record_id" => entry.id },
          on_replay: ->(reference) { BudgetItem.find(reference.fetch("id")) }
        ) do |operation|
          @mapping_store = TargetBackfill::MappingStore.new(
            workspace: workspace,
            operation_run: operation,
            version: MAPPING_VERSION
          )
          period = sync_period
          unless period.state_open? || period.state_reopened?
            raise ClosedPeriod, "Reopen #{entry.budget_month.label} before changing its plan"
          end
          item = sync_item(period, operation)
          sync_occurrence(item, period)
          sync_actual(item, operation)

          Platform::Operations::Executor::Completion.new(
            value: item,
            result_counts: { "budget_items" => 1 },
            result_reference: { "type" => "BudgetItem", "id" => item.id }
          )
        end
      end

      private

      attr_reader :context, :entry, :mapping_store

      delegate :membership, :workspace, to: :context

      def sync_period
        month = entry.budget_month
        period = mapping_store.target_for(source: month, target_class: BudgetPeriod) ||
          BudgetPeriod.find_or_initialize_by(budget_workspace: workspace, starts_on: month.month_on)
        period.assign_attributes(
          currency_code: workspace.default_currency_code,
          notes: month.notes,
          state: period.persisted? ? period.state : "open"
        )
        period.save!
        mapping_store.record!(
          source: month,
          target: period,
          source_attributes: month.attributes.slice("month_on", "notes", "leftover")
        )
        period
      end

      def sync_item(period, operation)
        item = mapping_store.target_for(source: entry, target_class: BudgetItem) ||
          mapping_store.build_target(source: entry, target_class: BudgetItem)
        action = item.persisted? ? "edit" : "create"
        item.assign_attributes(
          Platform::TargetTranslation::ExpenseEntry.call(
            entry: entry,
            workspace: workspace,
            period: period,
            category: resolve_category
          )
        )
        item.save!
        mapping_store.record!(source: entry, target: item, source_attributes: source_attributes)
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: membership,
          operation_run: operation,
          entity: item,
          action: action,
          changed_fields: item.previous_changes.keys - %w[created_at updated_at lock_version]
        )
        item
      end

      def resolve_category
        return if entry.category.blank?

        normalized_name = entry.category.strip
        category = workspace.categories.where("lower(name) = ?", normalized_name.downcase).first
        category ||= workspace.categories.create!(
          name: normalized_name,
          flow_kind: flow_kind,
          budget_group: budget_group,
          display_order: workspace.categories.maximum(:display_order).to_i + 1
        )
        return category if category.flow_kind == flow_kind

        raise CategorySemanticsConflict, "Category #{normalized_name.inspect} is already used for another flow"
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      def sync_occurrence(item, period)
        return unless entry.source_template_id.present? && entry.generated_entry_key.present?

        template = mapping_store.target_for(source: entry.source_template, target_class: PlanningTemplate)
        return if template.blank?

        occurrence = mapping_store.target_for(source: entry, target_class: RecurringOccurrence) ||
          RecurringOccurrence.find_or_initialize_by(
            planning_template: template,
            budget_period: period,
            scheduled_on: entry.occurred_on,
            slot_key: "default"
          )
        occurrence.assign_attributes(
          budget_workspace: workspace,
          budget_item: item,
          state: "materialized"
        )
        occurrence.save!
        item.update!(recurring_occurrence: occurrence) if item.recurring_occurrence_id != occurrence.id
        mapping_store.record!(
          source: entry,
          target: occurrence,
          source_attributes: entry.attributes.slice(
            "generated_entry_key", "occurred_on", "source_template_type", "source_template_id"
          )
        )
      end

      def sync_actual(item, operation)
        linked_transactions = mapped_linked_transactions
        if linked_transactions.any?
          reverse_synthetic_transaction(operation)
          linked_transactions.each { |transaction| sync_allocation(item, transaction, "exact_import") }
        elsif !entry.paid? || covered_by_legacy_import?
          reverse_synthetic_transaction(operation)
        else
          sync_synthetic_transaction(item, operation)
        end
      end

      def mapped_linked_transactions
        entry.account_activities.filter_map do |activity|
          transaction = mapping_store.target_for(source: activity, target_class: FinancialTransaction)
          if transaction.blank?
            raise MissingImportedTransaction, "Imported activity #{activity.id} has not been backfilled"
          end
          transaction
        end
      end

      def sync_synthetic_transaction(item, operation)
        amount = entry.effective_amount.to_d
        raise InvalidActual, "A paid entry must have a positive amount" unless amount.positive?

        transaction = mapping_store.target_for(source: entry, target_class: FinancialTransaction) ||
          mapping_store.build_target(source: entry, target_class: FinancialTransaction)
        action = transaction.persisted? ? "edit" : "create"
        transaction.assign_attributes(
          budget_workspace: workspace,
          effective_on: entry.occurred_on || entry.budget_month.month_on,
          description: entry.payee.presence || entry.category.presence || "Budget item actual",
          payee: entry.payee,
          memo: entry.notes,
          category: item.category,
          gross_amount: amount,
          currency_code: workspace.default_currency_code,
          flow_kind: flow_kind,
          state: "posted",
          origin_kind: "manual",
          idempotency_key: "legacy:expense-entry:#{entry.id}",
          voided_at: nil,
          void_reason: nil
        )
        transaction.save!
        sync_postings(transaction, amount)
        sync_allocation(item, transaction, "manual")
        mapping_store.record!(source: entry, target: transaction, source_attributes: source_attributes)
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: membership,
          operation_run: operation,
          entity: transaction,
          action: action,
          changed_fields: transaction.previous_changes.keys - %w[created_at updated_at lock_version]
        )
      end

      def sync_postings(transaction, amount)
        values = if flow_kind == "transfer"
          [ [ entry.source_account, -amount, "source" ], [ entry.destination_account, amount, "destination" ] ]
        elsif flow_kind == "income"
          [ [ entry.source_account || entry.destination_account, amount, "primary" ] ]
        else
          [ [ entry.source_account, -amount, "primary" ] ]
        end
        raise MissingAccount, "A paid entry must identify every affected account" if values.any? { |value| value.first.blank? }

        values.each_with_index do |(account, signed_amount, role), sequence_number|
          transaction.account_postings.find_or_initialize_by(sequence_number: sequence_number).tap do |posting|
            posting.assign_attributes(
              budget_workspace: workspace,
              account: account,
              amount: signed_amount,
              currency_code: workspace.default_currency_code,
              role: role
            )
            posting.save!
          end
        end
        transaction.account_postings.where.not(sequence_number: values.each_index.to_a).delete_all
      end

      def sync_allocation(item, transaction, match_kind)
        allocation = BudgetAllocation.find_or_initialize_by(
          budget_item: item,
          financial_transaction: transaction
        )
        allocation.assign_attributes(
          budget_workspace: workspace,
          amount: transaction.gross_amount,
          currency_code: workspace.default_currency_code,
          match_kind: match_kind,
          match_confidence: match_kind == "exact_import" ? 1 : nil,
          matched_by_membership: membership,
          matched_at: transaction.created_at || Time.current
        )
        allocation.save!
      end

      def reverse_synthetic_transaction(operation)
        transaction = mapping_store.target_for(source: entry, target_class: FinancialTransaction)
        return if transaction.blank? || transaction.state_reversed?

        transaction.update!(state: "reversed")
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: membership,
          operation_run: operation,
          entity: transaction,
          action: "reverse",
          changed_fields: %i[state]
        )
      end

      def covered_by_legacy_import?
        account = entry.source_account || entry.destination_account
        return false if account.blank? || entry.occurred_on.blank?

        account.account_activity_imports
          .where(started_on: ..entry.occurred_on)
          .where(ended_on: entry.occurred_on..)
          .exists?
      end

      def source_attributes
        @source_attributes ||= entry.attributes.except("created_at", "updated_at")
      end

      def flow_kind
        Platform::TargetTranslation::ExpenseEntry.flow_kind(entry)
      end

      def budget_group
        Platform::TargetTranslation::ExpenseEntry.budget_group(entry)
      end

      class CategorySemanticsConflict < WriteRejected; end
      class ClosedPeriod < WriteRejected; end
      class InvalidActual < WriteRejected; end
      class MissingAccount < WriteRejected; end
      class MissingImportedTransaction < WriteRejected; end
    end
  end
end
