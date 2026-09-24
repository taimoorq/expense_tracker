module BankConnections
  class UnacceptTransaction
    def self.call(source:, membership:)
      workspace = source.budget_workspace
      Access.authorize!(workspace: workspace, membership: membership)
      workspace.with_lock do
        source.reload
        transaction = source.financial_transaction
        return unless transaction
        dates = [ transaction.effective_on, *transaction.provider_transactions.map { |row| row.posted_at&.in_time_zone(workspace.time_zone)&.to_date } ].compact
        if workspace.budget_periods.where(starts_on: dates.map(&:beginning_of_month), state: %w[closing closed]).exists?
          raise ArgumentError, "Reopen the affected months before undoing accepted activity."
        end
        if source.resolution_kind == "existing"
          source.update!(state: "review", financial_transaction: nil, expense_entry: nil, resolution_kind: "imported")
          Audit::Recorder.call(workspace: workspace, actor_membership: membership, operation_run: nil, entity: source, action: "edit", changed_fields: %i[financial_transaction_id resolution_kind state])
          return
        end
        if transaction.provider_transactions.where(resolution_kind: "existing").exists?
          raise ArgumentError, "Detach the additional bank evidence before undoing this original transaction."
        end
        sources = transaction.provider_transactions.to_a
        entries = sources.filter_map(&:expense_entry).uniq
        transaction.payment_settlements.includes(:payment_commitment).each do |settlement|
          settlement.payment_commitment.update!(state: "reserved")
          settlement.destroy!
        end
        transaction.budget_allocations.destroy_all
        transaction.update!(state: "reversed")
        sources.each { |row| row.update!(state: "review", financial_transaction: nil, expense_entry: nil) }
        entries.each do |entry|
          remaining = entry.provider_transactions.includes(:financial_transaction).filter_map(&:financial_transaction).select(&:state_posted?).uniq.sum(&:gross_amount)
          entry.update!(actual_amount: remaining.positive? ? remaining : nil, status: remaining >= entry.planned_amount ? "paid" : "planned")
        end
        Audit::Recorder.call(workspace: workspace, actor_membership: membership, operation_run: nil, entity: transaction, action: "reverse", changed_fields: %i[state budget_allocations])
      end
    end
  end
end
