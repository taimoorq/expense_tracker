module Accounts
  class PlannedRemainders
    def self.call(workspace:, items:)
      return {} if items.empty?
      ids = items.map(&:id)
      allocated = workspace.budget_allocations.joins(:financial_transaction)
        .where(budget_item_id: ids, financial_transactions: { state: "posted" }).group(:budget_item_id).sum(:amount)
      entry_ids = workspace.legacy_record_mappings.status_mapped.where(target_record_type: "BudgetItem", target_record_id: ids, legacy_record_type: "ExpenseEntry").pluck(:target_record_id, :legacy_record_id).to_h
      entries = ExpenseEntry.where(id: entry_ids.values).index_by(&:id)
      reserved = workspace.payment_commitments.where(expense_entry_id: entry_ids.values, state: "reserved").includes(:payment_settlements).group_by(&:expense_entry_id)
      items.to_h do |item|
        entry = entries[entry_ids[item.id]]
        payments = reserved.fetch(entry&.id, [])
        remaining = [ item.planned_amount - allocated.fetch(item.id, 0) - payments.sum(&:outstanding_amount), 0.to_d ].max
        remaining = 0.to_d if entry&.paid? && payments.empty?
        [ item.id, remaining ]
      end
    end
  end
end
