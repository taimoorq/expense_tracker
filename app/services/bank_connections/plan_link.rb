module BankConnections
  # Compatibility linkage follows an explicit ledger allocation. Provider rows
  # remain the evidence; a match never creates a second transaction.
  class PlanLink
    def self.call(workspace:, transaction:, item:, entry:, unlink: false)
      return false unless transaction.provider_transactions.exists?
      raise Accounts::LegacyMatchBridge::MissingLegacyPair, "This plan has no editable month entry." unless entry
      sources = transaction.provider_transactions.to_a
      matching = sources.select { |source| [ entry.source_account_id, entry.destination_account_id ].include?(source.connected_account.account_id) }
      raise Accounts::LegacyMatchBridge::ConflictingLegacyMatch, "Choose a plan for the same account." if matching.empty?
      if matching.any? { |source| source.expense_entry_id && source.expense_entry_id != entry.id }
        raise Accounts::LegacyMatchBridge::ConflictingLegacyMatch, "This bank transaction already belongs to another plan. Unmatch it first."
      end
      unless unlink
        raise Accounts::LegacyMatchBridge::ConflictingLegacyMatch, "Resolve this plan's CSV match first." if entry.account_activities.exists?
        if item.financial_transactions.state_posted.where(origin_kind: "manual").where.not(id: transaction.id).where("financial_transactions.idempotency_key LIKE ?", "operation:%").exists?
          raise Accounts::LegacyMatchBridge::ConflictingLegacyMatch, "Attach the bank evidence to this plan's existing manual transaction instead."
        end
        matching.each do |source|
          expected = entry.source_account_id == source.connected_account.account_id ? (entry.income? ? 1 : -1) : 1
          unless expected.nonzero? && expected.positive? == source.amount.positive?
            raise Accounts::LegacyMatchBridge::ConflictingLegacyMatch, "The plan must move money in the same direction."
          end
        end
        mapping = workspace.legacy_record_mappings.status_mapped.find_by(legacy_record_type: "ExpenseEntry", legacy_record_id: entry.id, target_record_type: "FinancialTransaction")
        synthetic = workspace.financial_transactions.find_by(id: mapping&.target_record_id)
        synthetic.update!(state: "reversed") if synthetic&.origin_kind_manual?
      end
      matching.each { |source| source.update!(expense_entry: unlink ? nil : entry) }
      commitment = entry.payment_commitments.where(state: %w[reserved settled]).order(created_at: :desc).first
      if commitment
        settlement = commitment.payment_settlements.find_by(financial_transaction: transaction)
        if unlink
          settlement&.destroy!
          commitment.update!(state: "reserved")
        elsif matching.any? { |source| source.amount.negative? && source.connected_account.account_id == commitment.account_id } && !settlement
          amount = [ commitment.outstanding_amount, transaction.budget_allocations.find_by!(budget_item: item).amount ].min
          commitment.payment_settlements.create!(budget_workspace: workspace, financial_transaction: transaction, amount: amount) if amount.positive?
          commitment.update!(state: "settled") if commitment.outstanding_amount.zero?
        end
      end
      Accounts::PlanActualWriter.call(entry: entry, item: item)
      true
    end
  end
end
