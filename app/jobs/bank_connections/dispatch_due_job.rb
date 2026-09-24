module BankConnections
  class DispatchDueJob < ApplicationJob
    queue_as :maintenance

    def perform
      BankConnection.where(status: "active", automatic_refresh: true).where("next_refresh_at IS NULL OR next_refresh_at <= ?", Time.current).find_each do |connection|
        RefreshDispatch.call(connection: connection, membership: connection.actor_membership)
      rescue RefreshDispatch::Unavailable, Identity::WorkspaceAccess::NotAuthorized
        next
      end
      # A worker can die without executing rescue/ensure. Replay its durable run.
      BankRefresh.where("(state = 'running' AND lease_expires_at <= :now) OR (state = 'pending' AND updated_at <= :stale)", now: Time.current, stale: 10.minutes.ago).find_each do |refresh|
        RefreshJob.perform_later(refresh.operation_run_id)
      end
    end
  end
end
