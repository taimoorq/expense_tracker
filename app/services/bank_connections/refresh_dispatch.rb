module BankConnections
  class RefreshDispatch
    class Unavailable < StandardError; end

    def self.call(connection:, membership:, initial: false)
      Access.authorize!(workspace: connection.budget_workspace, membership: membership)
      refresh = connection.with_lock do
        existing = connection.bank_refreshes.find_by(state: %w[pending running])
        next existing if existing
        raise Unavailable, "Reconnect SimpleFIN before refreshing." unless connection.connected?
        if !initial && connection.last_checked_at && connection.last_checked_at > 15.minutes.ago
          raise Unavailable, "Refresh is available 15 minutes after the last check. Your bank may not have newer data yet."
        end
        now = Time.current
        operation = connection.budget_workspace.operation_runs.create!(
          actor_membership: membership, operation_type: "simplefin_refresh", idempotency_key: SecureRandom.uuid,
          request_digest: Platform::Operations::RequestDigest.for(connection_id: connection.id, generation: connection.credential_generation),
          redacted_parameters: { "bank_connection_id" => connection.id }, state: "pending", retryable: true,
          job_class: "BankConnections::RefreshJob", job_arguments: [], progress_current: 0, progress_total: 1
        )
        connection.bank_refreshes.create!(budget_workspace: connection.budget_workspace, operation_run: operation,
          credential_generation: connection.credential_generation, workspace_epoch: connection.budget_workspace.bank_sync_epoch,
          include_transactions: connection.connected_accounts.where(import_transactions: true).exists?,
          results: { "mapping_versions" => connection.connected_accounts.pluck(:id, :mapping_version).to_h })
      end
      Platform::Operations::Dispatcher.enqueue(refresh.operation_run)
      refresh
    end
  end
end
