module Accounts
  # The ledger command already owns posting and allocation changes. Updating the
  # compatibility entry here must not trigger a second synthetic transaction.
  class PlanActualWriter
    def self.call(entry:, item:)
      actual = item.budget_allocations.joins(:financial_transaction).where(financial_transactions: { state: "posted" }).sum(:amount)
      entry.update_columns(actual_amount: actual.positive? ? actual : nil,
        status: ExpenseEntry.statuses.fetch(actual >= item.planned_amount ? "paid" : "planned"),
        updated_at: Time.current, lock_version: entry.lock_version + 1)
    end
  end
end
