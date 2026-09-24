module BankConnections
  class Connect
    def self.call(workspace:, membership:, setup_token:, connection: nil, client: Simplefin::Client.new)
      Access.authorize!(workspace: workspace, membership: membership)
      raise ArgumentError, "The connection belongs to another workspace." if connection && connection.budget_workspace_id != workspace.id
      fingerprint = CredentialCodec.fingerprint(setup_token.to_s.strip)
      prior = workspace.bank_connections.find_by(claim_fingerprint: fingerprint)
      return prior if prior

      connection ||= workspace.bank_connections.create!(actor_membership: membership, claim_fingerprint: fingerprint)
      connection.with_lock do
        connection.bank_refreshes.where(state: %w[pending running]).each do |refresh|
          refresh.update!(state: "cancelled", completed_at: Time.current, lease_expires_at: nil)
          refresh.operation_run.update!(state: "failed", completed_at: Time.current, error_code: "reconnected")
        end
        connection.update!(status: "connecting", claim_fingerprint: fingerprint, encrypted_access_url: nil,
          credential_generation: connection.credential_generation + 1, automatic_refresh: false, error_message: nil)
      end
      generation = connection.credential_generation
      url = client.claim(setup_token)
      connection.with_lock do
        raise ArgumentError, "The connection changed while connecting. Generate a fresh token." unless connection.credential_generation == generation && connection.status == "connecting"
        connection.update!(access_url: url, status: "active")
      end
      RefreshDispatch.call(connection: connection, membership: membership, initial: true)
      connection
    rescue Simplefin::Client::Error => error
      connection&.with_lock do
        connection.update!(status: "needs_attention", error_message: error.message) if connection.credential_generation == generation && connection.status == "connecting"
      end
      raise
    rescue ActiveRecord::RecordNotUnique
      workspace.bank_connections.find_by!(claim_fingerprint: fingerprint)
    end
  end
end
