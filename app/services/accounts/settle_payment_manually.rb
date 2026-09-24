module Accounts
  class SettlePaymentManually
    def self.call(commitment:, membership:, cleared_on:)
      workspace = commitment.budget_workspace
      Identity::WorkspaceAccess.authorize_write!(workspace: workspace, membership: membership)
      workspace.with_lock do
        commitment.reload
        return commitment if commitment.state == "settled"
        raise ArgumentError, "This payment is no longer reserved." unless commitment.state == "reserved"
        raise ArgumentError, "The clearing date cannot precede the payment date." if cleared_on < commitment.initiated_on
        raise ArgumentError, "Confirm clearing only after the money has moved." if cleared_on > Time.current.in_time_zone(workspace.time_zone).to_date
        raise ArgumentError, "Finish the workspace ledger upgrade first." unless workspace.target_reads_enabled? && workspace.target_writes_enabled?
        entry = commitment.expense_entry
        raise ArgumentError, "This payment needs its original plan entry before it can be cleared." unless entry
        OpenPeriodGuard.call(workspace: workspace, dates: [ cleared_on, entry.occurred_on ])
        mapping = workspace.legacy_record_mappings.status_mapped.find_by!(legacy_record_type: "ExpenseEntry", legacy_record_id: entry.id, target_record_type: "BudgetItem")
        item = workspace.budget_items.find(mapping.target_record_id)
        OpenPeriodGuard.call(workspace: workspace, dates: [ item.budget_period.starts_on ])
        amount = commitment.outstanding_amount
        values = { effective_on: cleared_on, amount: amount, description: entry.payee.presence || entry.category.presence || "Cleared payment",
          flow_kind: commitment.destination_account ? "transfer" : "outflow", account: commitment.account,
          source_account: commitment.account, destination_account: commitment.destination_account }
        transaction = RecordManualTransaction.call(workspace: workspace, actor_membership: membership,
          idempotency_key: "manual-settlement:#{commitment.id}:#{SecureRandom.uuid}", attributes: values).value
        transaction.budget_allocations.create!(budget_workspace: workspace, budget_item: item, amount: amount,
          currency_code: commitment.currency_code, match_kind: "manual", matched_by_membership: membership, matched_at: Time.current)
        commitment.payment_settlements.create!(budget_workspace: workspace, financial_transaction: transaction, amount: amount)
        commitment.update!(state: "settled")
        PlanActualWriter.call(entry: entry, item: item)
        commitment
      end
    end
  end
end
