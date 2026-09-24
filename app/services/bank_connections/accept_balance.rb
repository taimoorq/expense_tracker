module BankConnections
  class AcceptBalance
    def self.call(mapping:, membership:, balance_id:, mapping_version:, dispositions:, coverage:, confirmed:)
      workspace = mapping.budget_workspace
      Access.authorize!(workspace: workspace, membership: membership)
      raise ArgumentError, "Confirm that you reviewed this balance and its recorded activity." unless confirmed
      raise ArgumentError, "Finish the workspace ledger migration before using bank balances in calculations." unless workspace.target_reads_enabled? && workspace.target_writes_enabled?
      ApplicationRecord.transaction do
        workspace.lock!
        mapping.lock!
        balance = mapping.provider_balances.find(balance_id)
        unless mapping.account && mapping.mapping_version == mapping_version.to_i && mapping.latest_balance&.id == balance.id
          raise ArgumentError, "The account or balance changed. Review its latest version."
        end
        commitments = mapping.account.payment_commitments.where(state: "reserved").lock.to_a
        if commitments.map(&:id).sort != dispositions.keys.sort || dispositions.values.any? { |value| !value.in?(%w[included outside]) }
          raise ArgumentError, "Recorded payments changed. Review every outstanding payment again."
        end
        candidates = Review.new(mapping: mapping, balance: balance).transactions
        if candidates.map(&:id).sort != coverage.keys.sort || coverage.values.any? { |value| !value.in?(%w[included outside]) }
          raise ArgumentError, "Recorded activity changed. Review every listed transaction again."
        end
        observation = BalanceObservation.find_or_initialize_by(provider_balance: balance)
        observation.assign_attributes(budget_workspace: workspace, account: mapping.account, actor_membership: membership,
          balance: balance.normalized_balance, available_balance: balance.available_balance, currency_code: balance.currency,
          source_kind: "bank_sync", status: "trusted", observed_at: balance.fetched_at, effective_through_at: balance.reported_at,
          transaction_coverage: coverage)
        observation.save!
        commitments.each do |commitment|
          if dispositions.fetch(commitment.id) == "included"
            commitment.update!(included_provider_balance: balance, excluded_provider_balance_id: nil)
          else
            commitment.update!(included_provider_balance: nil, excluded_provider_balance_id: balance.id)
          end
        end
        balance.update!(state: "accepted")
        mapping.update!(use_bank_balance: true)
        Audit::Recorder.call(workspace: workspace, actor_membership: membership, operation_run: nil,
          entity: observation, action: "trust_observation", changed_fields: %i[balance effective_through_at transaction_coverage])
        observation
      end
    end
  end
end
