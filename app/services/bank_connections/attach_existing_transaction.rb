module BankConnections
  class AttachExistingTransaction
    def self.call(source:, transaction:, membership:, digest:)
      workspace = source.budget_workspace
      Access.authorize!(workspace: workspace, membership: membership)
      workspace.with_lock do
        source.reload
        transaction.reload
        raise ArgumentError, "Finish the workspace ledger upgrade first." unless workspace.target_reads_enabled? && workspace.target_writes_enabled?
        raise ArgumentError, "Review the latest posted bank transaction." if source.pending? || source.posted_at.nil? || source.content_digest != digest
        return transaction if source.financial_transaction_id == transaction.id && source.resolution_kind == "existing"
        raise ArgumentError, "Undo the existing acceptance before resolving this source." if source.financial_transaction_id
        posting = transaction.account_postings.find_by(account_id: source.connected_account.account_id)
        unless transaction.budget_workspace_id == workspace.id && transaction.state_posted? &&
            posting && posting.amount == source.amount && posting.currency_code == source.currency
          raise ArgumentError, "Choose a posted transaction with the same amount, direction, currency, and account."
        end
        Accounts::OpenPeriodGuard.call(workspace: workspace, dates: [ transaction.effective_on, source.posted_at.in_time_zone(workspace.time_zone).to_date ])
        source.update!(financial_transaction: transaction, expense_entry: nil, resolution_kind: "existing", state: "accepted")
        Audit::Recorder.call(workspace: workspace, actor_membership: membership, operation_run: nil,
          entity: source, action: "edit", changed_fields: %i[financial_transaction_id resolution_kind state])
        transaction
      end
    end
  end
end
