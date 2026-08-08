module Platform
  module TargetSync
    class BudgetMonthWriter
      def self.call(budget_month:)
        new(budget_month: budget_month).call
      end

      def initialize(budget_month:)
        @budget_month = budget_month
      end

      def call
        @context = Context.for(budget_month)
        return if context.blank?

        sync_period
        budget_month.expense_entries.find_each { |entry| ExpenseEntryWriter.call(entry: entry) }
      end

      private

      attr_reader :budget_month, :context

      delegate :membership, :workspace, to: :context

      def sync_period
        Platform::Operations::Executor.call(
          workspace: workspace,
          actor_membership: membership,
          operation_type: "sync_legacy_budget_month",
          idempotency_key: "legacy:BudgetMonth:#{budget_month.id}:#{budget_month.lock_version}",
          request: budget_month.attributes.except("created_at", "updated_at"),
          redacted_parameters: { "legacy_record_type" => "BudgetMonth", "legacy_record_id" => budget_month.id },
          on_replay: ->(reference) { BudgetPeriod.find(reference.fetch("id")) }
        ) do |operation|
          mapping_store = TargetBackfill::MappingStore.new(
            workspace: workspace,
            operation_run: operation,
            version: ExpenseEntryWriter::MAPPING_VERSION
          )
          period = mapping_store.target_for(source: budget_month, target_class: BudgetPeriod) ||
            BudgetPeriod.find_or_initialize_by(
              budget_workspace: workspace,
              starts_on: budget_month.month_on
            )
          action = period.persisted? ? "edit" : "create"
          period.assign_attributes(
            currency_code: workspace.default_currency_code,
            notes: budget_month.notes,
            state: period.persisted? ? period.state : "open"
          )
          period.save!
          mapping_store.record!(
            source: budget_month,
            target: period,
            source_attributes: budget_month.attributes.slice("month_on", "notes", "leftover")
          )
          Audit::Recorder.call(
            workspace: workspace,
            actor_membership: membership,
            operation_run: operation,
            entity: period,
            action: action,
            changed_fields: period.previous_changes.keys - %w[created_at updated_at lock_version]
          )
          Platform::Operations::Executor::Completion.new(
            value: period,
            result_counts: { "budget_periods" => 1 },
            result_reference: { "type" => "BudgetPeriod", "id" => period.id }
          )
        end
      end
    end
  end
end
