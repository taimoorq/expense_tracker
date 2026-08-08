module Platform
  module Backup
    class ReplacementCleaner
      def self.call(user:, workspace:)
        new(user: user, workspace: workspace).call
      end

      def initialize(user:, workspace:)
        @user = user
        @workspace = workspace
      end

      def call
        raise ArgumentError, "The workspace does not belong to this user." unless workspace.legacy_owner_user_id == user.id

        workspace.update!(target_reads_enabled: false, target_writes_enabled: false)
        clear_target_data
        clear_legacy_data
      end

      private

      attr_reader :user, :workspace

      def clear_target_data
        delete_workspace_records(MonthCloseItemSnapshot)
        delete_workspace_records(MonthCloseTransactionSnapshot)
        delete_workspace_records(BudgetAllocation)
        delete_workspace_records(AccountPosting)
        delete_workspace_records(BalanceObservation)
        workspace.import_rows.update_all(financial_transaction_id: nil)
        workspace.financial_transactions.update_all(import_row_id: nil, reversal_transaction_id: nil)
        delete_workspace_records(ImportRow)
        delete_workspace_records(ImportBatch)
        delete_workspace_records(ImportProfile)
        delete_workspace_records(MonthClose)
        workspace.budget_items.update_all(recurring_occurrence_id: nil)
        workspace.recurring_occurrences.update_all(budget_item_id: nil)
        delete_workspace_records(BudgetItem)
        delete_workspace_records(RecurringOccurrence)
        clear_planning_template_details
        delete_workspace_records(PlanningTemplate)
        delete_workspace_records(FinancialTransaction)
        delete_workspace_records(Category)
        delete_workspace_records(BudgetPeriod)
        delete_workspace_records(LegacyRecordMapping)
        delete_workspace_records(MigrationDiscrepancy)
      end

      def delete_workspace_records(model)
        model.where(budget_workspace_id: workspace.id).delete_all
      end

      def clear_planning_template_details
        template_ids = workspace.planning_templates.select(:id)
        RecurrenceMonth.where(recurrence_rule_id: RecurrenceRule.where(planning_template_id: template_ids).select(:id)).delete_all
        RecurrenceRule.where(planning_template_id: template_ids).delete_all
        PaymentPlanTerm.where(planning_template_id: template_ids).delete_all
        CreditCardPaymentPolicy.where(planning_template_id: template_ids).delete_all
      end

      def clear_legacy_data
        user.account_activity_imports.destroy_all
        user.budget_months.destroy_all
        user.pay_schedules.destroy_all
        user.subscriptions.destroy_all
        user.monthly_bills.destroy_all
        user.payment_plans.destroy_all
        user.credit_cards.destroy_all
        user.accounts.destroy_all
        workspace.update!(target_backfill_version: nil, target_backfilled_at: nil)
      end
    end
  end
end
