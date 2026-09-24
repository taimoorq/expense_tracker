module BankConnections
  class AccountEvidence
    def self.call(accounts)
      mappings = ConnectedAccount.where(account_id: Array(accounts).map(&:id)).includes(:bank_connection, :budget_workspace).to_a
      balances = ProviderBalance.where(connected_account_id: mappings.map(&:id)).where.not(state: "disputed")
        .select("DISTINCT ON (connected_account_id) provider_balances.*").order(:connected_account_id, reported_at: :desc, created_at: :desc).index_by(&:connected_account_id)
      mappings.index_by(&:account_id).transform_values { |mapping| { mapping: mapping, balance: balances[mapping.id] } }
    end
  end
end
