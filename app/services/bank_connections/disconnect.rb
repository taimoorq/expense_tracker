module BankConnections
  class Disconnect
    def self.call(connection:, membership:)
      Access.authorize!(workspace: connection.budget_workspace, membership: membership)
      connection.with_lock do
        connection.update!(status: "disconnected", encrypted_access_url: nil, automatic_refresh: false,
          credential_generation: connection.credential_generation + 1, next_refresh_at: nil)
        connection.bank_refreshes.where(state: %w[pending running]).find_each do |refresh|
          refresh.update!(state: "cancelled", completed_at: Time.current)
          refresh.operation_run.update!(state: "failed", completed_at: Time.current, error_code: "bank_disconnected", retryable: false)
        end
      end
    end
  end
end
