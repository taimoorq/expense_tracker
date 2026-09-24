module BankConnections
  class AutoAcceptBalance
    def self.call(mapping:, membership:, generation:)
      workspace = mapping.budget_workspace
      return unless workspace.target_reads_enabled? && mapping.use_bank_balance? && mapping.account
      workspace.with_lock do
        connection = mapping.bank_connection.reload
        return unless connection.connected? && connection.credential_generation == generation
        balance = mapping.latest_balance
        return unless balance && balance.state == "reported" && mapping.error_message.blank?
        return if mapping.account.payment_commitments.where(state: "reserved").exists?
        candidates = Review.new(mapping: mapping, balance: balance).transactions
        postings = mapping.account.account_postings.where(financial_transaction_id: candidates.map(&:id)).includes(:financial_transaction).index_by(&:financial_transaction_id)
        coverage = candidates.to_h do |transaction|
          instant = postings[transaction.id]&.effective_at || transaction.posted_at || transaction.transacted_at
          return unless instant # Assumed ordering times are not bank evidence.
          [ transaction.id, instant <= balance.reported_at ? "included" : "outside" ]
        end
        AcceptBalance.call(mapping: mapping, membership: membership, balance_id: balance.id,
          mapping_version: mapping.mapping_version, dispositions: {}, coverage: coverage, confirmed: true)
      end
    rescue ArgumentError, Identity::WorkspaceAccess::NotAuthorized
      # A concurrent payment or mapping change leaves this balance for review.
      nil
    end
  end
end
