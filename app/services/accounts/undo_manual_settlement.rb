module Accounts
  class UndoManualSettlement
    def self.call(settlement:, membership:)
      workspace = settlement.budget_workspace
      Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: membership)
      workspace.with_lock do
        transaction = settlement.financial_transaction
        commitment = settlement.payment_commitment
        unless transaction.origin_kind_manual? && transaction.provider_transactions.empty?
          raise ArgumentError, "Detach or undo the bank evidence through bank review first."
        end
        plan_dates = transaction.budget_items.joins(:budget_period).pluck("budget_periods.starts_on")
        OpenPeriodGuard.call(workspace: workspace, dates: plan_dates + [ transaction.effective_on, commitment.expense_entry&.occurred_on ])
        transaction.budget_allocations.destroy_all
        transaction.update!(state: "reversed")
        settlement.destroy!
        commitment.update!(state: "reserved")
        Audit::Recorder.call(workspace: workspace, actor_membership: membership, operation_run: nil,
          entity: transaction, action: "reverse", changed_fields: %i[state payment_settlements])
      end
    end
  end
end
