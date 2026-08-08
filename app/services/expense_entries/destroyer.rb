module ExpenseEntries
  class Destroyer
    def self.call(expense_entry:, reason: "Deleted from legacy plan")
      new(expense_entry: expense_entry, reason: reason).call
    end

    def initialize(expense_entry:, reason:)
      @expense_entry = expense_entry
      @reason = reason
    end

    def call
      ApplicationRecord.transaction do
        expense_entry.lock!
        sync_target
        expense_entry.destroy!
      end
      true
    rescue Platform::TargetSync::WriteRejected => error
      expense_entry.errors.add(:base, error.message)
      false
    end

    private

    attr_reader :expense_entry, :reason

    def sync_target
      context = Platform::TargetSync::Context.for(expense_entry)
      return if context.blank?

      workspace = context.workspace
      membership = context.membership
      Platform::Operations::Executor.call(
        workspace: workspace,
        actor_membership: membership,
        operation_type: "void_legacy_expense_entry",
        idempotency_key: "legacy:ExpenseEntry:#{expense_entry.id}:#{expense_entry.lock_version}:void",
        request: { expense_entry_id: expense_entry.id, lock_version: expense_entry.lock_version },
        redacted_parameters: { "legacy_record_type" => "ExpenseEntry", "legacy_record_id" => expense_entry.id },
        on_replay: ->(reference) { BudgetItem.find(reference.fetch("id")) }
      ) do |operation|
        mapping_store = Platform::TargetBackfill::MappingStore.new(
          workspace: workspace,
          operation_run: operation,
          version: Platform::TargetSync::ExpenseEntryWriter::MAPPING_VERSION
        )
        item = mapping_store.target_for(source: expense_entry, target_class: BudgetItem)
        raise MissingMapping, "The planned item has not been synchronized" if item.blank?
        unless item.budget_period.state_open? || item.budget_period.state_reopened?
          raise Platform::TargetSync::ExpenseEntryWriter::ClosedPeriod,
            "Reopen #{expense_entry.budget_month.label} before deleting its plan"
        end

        cancel_occurrence(item)
        item.update!(state: "voided", voided_at: Time.current, void_reason: reason, recurring_occurrence: nil)
        transaction = mapping_store.target_for(source: expense_entry, target_class: FinancialTransaction)
        transaction.update!(state: "reversed") if transaction.present? && !transaction.state_reversed?
        workspace.legacy_record_mappings.where(
          legacy_record_type: "ExpenseEntry",
          legacy_record_id: expense_entry.id
        ).update_all(status: "omitted", metadata: { "void_reason" => reason }, updated_at: Time.current)
        Audit::Recorder.call(
          workspace: workspace,
          actor_membership: membership,
          operation_run: operation,
          entity: item,
          action: "void",
          changed_fields: %i[state voided_at void_reason]
        )
        Platform::Operations::Executor::Completion.new(
          value: item,
          result_counts: { "budget_items_voided" => 1, "transactions_reversed" => transaction.present? ? 1 : 0 },
          result_reference: { "type" => "BudgetItem", "id" => item.id }
        )
      end
    end

    def cancel_occurrence(item)
      occurrence = item.recurring_occurrence
      return if occurrence.blank?

      occurrence.update!(state: "cancelled", budget_item: nil)
    end

    class MissingMapping < Platform::TargetSync::WriteRejected; end
  end
end
