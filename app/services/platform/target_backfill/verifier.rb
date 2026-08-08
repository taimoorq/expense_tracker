module Platform
  module TargetBackfill
    class Verifier
      Check = Data.define(:key, :passed, :kind)
      Result = Data.define(:workspace, :checks, :open_discrepancy_count) do
        def clean?
          checks.all?(&:passed) && open_discrepancy_count.zero?
        end

        def as_json(*)
          {
            workspace_id: workspace.id,
            clean: clean?,
            checks: checks.map { |check| { key: check.key, passed: check.passed, kind: check.kind } },
            open_discrepancy_count: open_discrepancy_count
          }
        end
      end

      def self.call(user:, workspace:, operation_run:, persist: true)
        new(user: user, workspace: workspace, operation_run: operation_run, persist: persist).call
      end

      def initialize(user:, workspace:, operation_run:, persist:)
        @user = user
        @workspace = workspace
        @operation_run = operation_run
        @persist = persist
        @mapping_store = MappingStore.new(workspace: workspace, operation_run: operation_run)
      end

      def call
        checks = mapping_checks + financial_checks
        checks.each { |check| sync_check_discrepancy(check) } if persist
        open_count = workspace.migration_discrepancies.status_open.count

        Result.new(workspace: workspace, checks: checks, open_discrepancy_count: open_count)
      end

      private

      attr_reader :mapping_store, :operation_run, :persist, :user, :workspace

      def mapping_checks
        [
          mapping_check(:account_mappings, Account, Account, user.accounts.count),
          mapping_check(:period_mappings, BudgetMonth, BudgetPeriod, user.budget_months.count),
          mapping_check(:item_mappings, ExpenseEntry, BudgetItem, user.expense_entries.count),
          mapping_check(:template_mappings, nil, PlanningTemplate, legacy_template_count),
          mapping_check(:occurrence_mappings, ExpenseEntry, RecurringOccurrence, generated_entry_count),
          mapping_check(:snapshot_mappings, AccountSnapshot, BalanceObservation, user.account_snapshots.count),
          mapping_check(:import_batch_mappings, AccountActivityImport, ImportBatch, user.account_activity_imports.count),
          mapping_check(:import_row_mappings, AccountActivity, ImportRow, user.account_activities.count),
          mapping_check(:import_transaction_mappings, AccountActivity, FinancialTransaction, user.account_activities.count),
          Check.new(key: :mapping_targets_exist, passed: missing_mapping_target_count.zero?, kind: :count)
        ]
      end

      def mapping_check(key, source_class, target_class, expected)
        scope = workspace.legacy_record_mappings.where(target_record_type: target_class.name)
        scope = scope.where(legacy_record_type: source_class.name) if source_class.present?
        Check.new(key: key, passed: scope.count == expected, kind: :count)
      end

      def financial_checks
        paid_result = paid_allocation_result
        [
          Check.new(key: :planned_amount_parity, passed: legacy_planned_amount == target_planned_amount, kind: :money),
          Check.new(key: :paid_allocation_parity, passed: paid_result[:mismatch_count].zero?, kind: :money),
          Check.new(key: :paid_entries_classified, passed: paid_result[:unclassified_count].zero?, kind: :count),
          Check.new(key: :allocations_within_transactions, passed: overallocated_transaction_count.zero?, kind: :money),
          Check.new(key: :transfer_postings_balance, passed: unbalanced_transfer_count.zero?, kind: :money),
          Check.new(key: :posted_transactions_have_postings, passed: posted_without_posting_count.zero?, kind: :count)
        ]
      end

      def legacy_planned_amount
        user.expense_entries.where.not(status: ExpenseEntry.statuses.fetch("skipped")).sum(:planned_amount)
      end

      def target_planned_amount
        workspace.budget_items.where.not(state: %w[skipped cancelled voided]).sum(:planned_amount)
      end

      def paid_allocation_result
        mismatch_count = 0
        unclassified_count = 0

        user.expense_entries
          .paid
          .includes(:account_activities, source_account: :account_activity_imports, destination_account: :account_activity_imports)
          .find_each do |entry|
          item = mapped_target(entry, BudgetItem)
          if item.blank?
            unclassified_count += 1
            next
          end

          linked_amount = entry.account_activities.sum(&:amount)
          expected_amount = if entry.account_activities.any?
            linked_amount
          elsif paid_entry_covered_by_import?(entry)
            unclassified_count += 1
            0
          else
            entry.effective_amount
          end
          mismatch_count += 1 unless item.budget_allocations.sum(:amount) == expected_amount
        end

        { mismatch_count: mismatch_count, unclassified_count: unclassified_count }
      end

      def paid_entry_covered_by_import?(entry)
        account = entry.source_account || entry.destination_account
        return false if account.blank? || entry.occurred_on.blank?

        account.account_activity_imports
          .where(started_on: ..entry.occurred_on)
          .where(ended_on: entry.occurred_on..)
          .exists?
      end

      def overallocated_transaction_count
        workspace.financial_transactions
          .joins(:budget_allocations)
          .group("financial_transactions.id")
          .having("SUM(budget_allocations.amount) > financial_transactions.gross_amount")
          .count
          .size
      end

      def unbalanced_transfer_count
        workspace.financial_transactions
          .where(flow_kind: "transfer")
          .left_joins(:account_postings)
          .group("financial_transactions.id")
          .having("COALESCE(SUM(account_postings.amount), 0) <> 0")
          .count
          .size
      end

      def posted_without_posting_count
        workspace.financial_transactions
          .where(state: "posted")
          .left_joins(:account_postings)
          .group("financial_transactions.id")
          .having("COUNT(account_postings.id) = 0")
          .count
          .size
      end

      def legacy_template_count
        PlanningBackfill::TEMPLATE_MODELS.sum { |model| model.where(user_id: user.id).count }
      end

      def generated_entry_count
        user.expense_entries.where.not(source_template_id: nil).where.not(generated_entry_key: nil).count
      end

      def missing_mapping_target_count
        workspace.legacy_record_mappings.group_by(&:target_record_type).sum do |target_type, mappings|
          model = target_type.safe_constantize
          next mappings.size if model.blank? || !model.respond_to?(:where)

          mappings.size - model.where(id: mappings.map(&:target_record_id)).count
        end
      end

      def mapped_target(source, target_class)
        mapping_store.target_for(source: source, target_class: target_class)
      end

      def sync_check_discrepancy(check)
        code = "verification_#{check.key}"
        discrepancy = workspace.migration_discrepancies.find_by(
          legacy_record_type: "User",
          legacy_record_id: user.id,
          code: code
        )

        if check.passed
          discrepancy&.update!(status: "resolved", resolved_at: Time.current)
        else
          mapping_store.record_discrepancy!(
            source: user,
            code: code,
            details: { "kind" => check.kind.to_s }
          )
        end
      end
    end
  end
end
