module Accounts
  class ManualPlanLink
    def self.call(workspace:, transaction:, item:, entry:, unlink: false)
      return false unless entry && transaction.origin_kind_manual? && transaction.idempotency_key.to_s.start_with?("operation:")
      if transaction.payment_settlements.exists?
        raise LegacyMatchBridge::ConflictingLegacyMatch, "Undo payment clearing before changing this match."
      end
      unless unlink
        posting = transaction.account_postings.find_by(account_id: entry.source_account_id || entry.destination_account_id)
        unless posting && posting.amount.positive? == entry.income? && transaction.flow_kind == item.flow_kind
          raise LegacyMatchBridge::ConflictingLegacyMatch, "Choose a plan with the same account and direction."
        end
        if transaction.flow_kind_transfer? && !transaction.account_postings.exists?(account_id: entry.destination_account_id, role: "destination")
          raise LegacyMatchBridge::ConflictingLegacyMatch, "Choose a transfer plan with the same destination account."
        end
        if entry.account_activities.exists? || entry.provider_transactions.where.not(financial_transaction_id: nil).exists? || entry.payment_commitments.where(state: "reserved").exists?
          raise LegacyMatchBridge::ConflictingLegacyMatch, "Resolve the plan's existing activity or clear its reserved payment first."
        end
        mapping = workspace.legacy_record_mappings.status_mapped.find_by(legacy_record_type: "ExpenseEntry", legacy_record_id: entry.id, target_record_type: "FinancialTransaction")
        synthetic = workspace.financial_transactions.find_by(id: mapping&.target_record_id)
        synthetic.update!(state: "reversed") if synthetic && synthetic != transaction
      end
      PlanActualWriter.call(entry: entry, item: item)
      true
    end
  end
end
