module Overview
  class WorkflowStatus
    Result = Data.define(:workspace, :membership, :ledger_ready, :connections_count,
      :bank_review_count, :pending_count, :connection_attention_count, :reserved_count)

    def self.call(user:)
      context = Identity::PersonalWorkspaceProvisioner.call(user: user)
      workspace = context.workspace
      sources = workspace.provider_transactions.joins(:connected_account)
        .where(connected_accounts: { state: "mapped" }).where.not(connected_accounts: { account_id: nil })
      source_counts = sources.group(:state, :pending).count
      connection_counts = workspace.bank_connections.group(:status).count
      context.membership.budget_workspace = workspace
      Result.new(workspace: workspace, membership: context.membership,
        ledger_ready: workspace.target_reads_enabled? && workspace.target_writes_enabled?,
        connections_count: connection_counts.values.sum,
        bank_review_count: source_counts.sum { |(state, pending), count| state.in?(%w[review changed]) && !pending ? count : 0 },
        pending_count: source_counts.sum { |(state, pending), count| state.in?(%w[review changed]) && pending ? count : 0 },
        connection_attention_count: connection_counts.values_at("needs_attention", "connecting").compact.sum,
        reserved_count: workspace.payment_commitments.where(state: "reserved").count)
    end
  end
end
