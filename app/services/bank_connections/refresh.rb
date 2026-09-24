module BankConnections
  class Refresh
    class Stale < StandardError; end
    class Busy < StandardError; end
    MAX_ATTEMPTS = 3

    def initialize(refresh:, client: Simplefin::Client.new)
      @refresh, @client = refresh, client
      @connection = refresh.bank_connection
      @workspace = refresh.budget_workspace
      @membership = refresh.operation_run.actor_membership
    end

    def call
      return refresh if refresh.terminal?
      Access.authorize!(workspace: workspace, membership: membership)
      acquire!
      raise Simplefin::Client::Error.new(:exhausted, "This refresh could not finish after three attempts. Start a new refresh.") if refresh.attempts > MAX_ATTEMPTS
      payload = client.accounts(connection.access_url, transactions: refresh.include_transactions?, start_at: start_at)
      fetched_at = Time.current
      errors = Simplefin::Normalizer.errors(payload)
      outcomes = {}
      seen = []
      payload.fetch("accounts").each do |raw|
        apply_account(raw, payload, fetched_at, errors, outcomes, seen)
      end
      connection.with_lock do
        verify!
        connection.connected_accounts.where.not(id: seen).where(state: "mapped").update_all(state: "missing", error_message: "This account was not returned by SimpleFIN. Its last saved data is retained.")
        mark_completed!(outcomes, errors)
      end
      outcomes.each do |mapping_id, outcome|
        next unless outcome["state"] == "updated"
        AutoAcceptBalance.call(mapping: connection.connected_accounts.find(mapping_id), membership: membership, generation: refresh.credential_generation)
      end
      refresh
    rescue Simplefin::Client::Error => error
      fail_attempt!(error)
      raise if error.retryable? && refresh.attempts < MAX_ATTEMPTS
      refresh
    rescue Stale, Identity::WorkspaceAccess::NotAuthorized
      finish_cancelled!
      refresh
    rescue Busy
      refresh
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { operation: "simplefin_refresh", refresh_id: refresh.id })
      fail_attempt!(Simplefin::Client::Error.new(:unexpected_response, "This refresh could not be processed. Saved balances and activity were kept."))
      refresh
    end

    private

    attr_reader :refresh, :client, :connection, :workspace, :membership, :lease

    def acquire!
      connection.with_lock do
        refresh.reload
        raise Stale if refresh.terminal?
        verify_identity!
        raise Busy if refresh.lease_expires_at && refresh.lease_expires_at > Time.current
        times = connection.request_times.filter_map { |value| Time.iso8601(value) rescue nil }.select { |time| time > 24.hours.ago }
        if times.size >= 12
          raise Simplefin::Client::Error.new(:rate_limit, "The app's daily refresh allowance has been used. Try again after #{(times.min + 24.hours).utc.iso8601}.")
        end
        @lease = SecureRandom.uuid
        refresh.update!(state: "running", attempts: refresh.attempts + 1, started_at: refresh.started_at || Time.current,
          lease_token: lease, lease_expires_at: 5.minutes.from_now)
        connection.update!(request_times: (times + [ Time.current ]).map(&:iso8601), last_checked_at: Time.current)
        refresh.operation_run.update!(state: "running", started_at: Time.current, progress_label: "Checking SimpleFIN", last_heartbeat_at: Time.current)
      end
    end

    def start_at
      dates = connection.connected_accounts.where(import_transactions: true).pluck(:transactions_through_at)
      [ dates.compact.min&.-(5.days) || 30.days.ago, 89.days.ago ].max
    end

    def verify_identity!
      workspace.reload
      unless connection.connected? && connection.credential_generation == refresh.credential_generation && workspace.bank_sync_epoch == refresh.workspace_epoch
        raise Stale
      end
      Access.authorize!(workspace: workspace, membership: membership.reload)
    end

    def verify!
      refresh.reload
      verify_identity!
      raise Stale unless refresh.lease_token == lease && refresh.lease_expires_at&.future? && refresh.state == "running"
    end

    def apply_account(raw, payload, fetched_at, errors, outcomes, seen)
      raise Simplefin::Normalizer::Invalid, "An account is not an object." unless raw.is_a?(Hash)
      provider_id = Simplefin::Normalizer.identity(raw["id"])
      institution_id = Simplefin::Normalizer.identity(raw["conn_id"])
      connection.with_lock do
        verify!
        refresh.update!(lease_expires_at: 5.minutes.from_now)
        mapping = connection.connected_accounts.find_or_initialize_by(provider_connection_id: institution_id, provider_account_id: provider_id)
        versions = refresh.results.fetch("mapping_versions", {})
        raise Stale if mapping.persisted? && versions[mapping.id] && versions[mapping.id] != mapping.mapping_version
        institution = Array(payload["connections"]).find { |value| value.is_a?(Hash) && value["conn_id"] == institution_id } || {}
        mapping.assign_attributes(budget_workspace: workspace, name: Simplefin::Normalizer.text(raw["name"], required: true),
          institution_name: Simplefin::Normalizer.text(institution["name"].presence || institution["org_name"].presence || "Institution"),
          currency: Simplefin::Normalizer.text(raw["currency"], required: true), last_seen_at: fetched_at, last_checked_at: fetched_at)
        mapping.state = "mapped" if mapping.account_id.present? && mapping.state == "missing"
        mapping.error_message = errors.select { |error| error["account_id"] == provider_id || error["connection_id"] == institution_id }.map { |error| error["message"] }.join(" ").presence
        mapping.save!
        seen << mapping.id
        next if mapping.state == "ignored"
        unless mapping.supported_currency?
          mapping.update!(error_message: "This currency is not supported in this workspace.")
          outcomes[mapping.id] = { "state" => "unsupported_currency" }
          next
        end
        balance = persist_balance(mapping, raw, fetched_at)
        mapping.update!(error_message: "The bank revised a balance at the same source time. The previous accepted balance was kept; verify the balance with your bank.") if balance.state == "disputed"
        outcomes[mapping.id] = { "state" => mapping.error_message ? "partial" : "updated", "balance_id" => balance.id }
        if refresh.include_transactions? && mapping.import_transactions? && mapping.account_id.present?
          begin
            ApplicationRecord.transaction(requires_new: true) { persist_transactions(mapping, raw, fetched_at) }
            mapping.update!(transactions_through_at: fetched_at) unless mapping.error_message
          rescue Simplefin::Normalizer::Invalid, ActiveRecord::RecordInvalid => error
            mapping.update!(error_message: Simplefin::Normalizer.safe_message(error.message))
            outcomes[mapping.id]["state"] = "partial"
            errors << { "code" => "invalid_transactions", "account_id" => provider_id, "message" => mapping.error_message }
          end
        end
      end
    rescue Simplefin::Normalizer::Invalid, ActiveRecord::RecordInvalid => error
      errors << { "code" => "invalid_account", "account_id" => provider_id, "message" => Simplefin::Normalizer.safe_message(error.message) }
    end

    def persist_balance(mapping, raw, fetched_at)
      balance = Simplefin::Normalizer.money(raw["balance"])
      available = Simplefin::Normalizer.money(raw["available-balance"], optional: true)
      reported_at = Simplefin::Normalizer.time(raw["balance-date"], fetched_at: fetched_at)
      digest = Digest::SHA256.hexdigest([ balance.to_s("F"), available&.to_s("F"), mapping.currency ].join("|"))
      prior = mapping.provider_balances.find_by(reported_at: reported_at)
      row = mapping.provider_balances.find_or_create_by!(reported_at: reported_at, content_digest: digest) do |record|
        record.assign_attributes(budget_workspace: workspace, bank_refresh: refresh, balance: balance, available_balance: available,
          currency: mapping.currency, fetched_at: fetched_at, state: prior && prior.content_digest != digest ? "disputed" : "reported")
      end
      row
    end

    def persist_transactions(mapping, raw, fetched_at)
      rows = raw["transactions"]
      raise Simplefin::Normalizer::Invalid, "Transaction history is missing or too large." unless rows.is_a?(Array) && rows.size <= 10_000
      rows.each do |source|
        raise Simplefin::Normalizer::Invalid, "A transaction is not an object." unless source.is_a?(Hash)
        attributes = {
          amount: Simplefin::Normalizer.money(source["amount"]), currency: mapping.currency,
          description: Simplefin::Normalizer.text(source["description"], required: true),
          posted_at: Simplefin::Normalizer.time(source["posted"], fetched_at: fetched_at, optional: source["pending"] == true),
          transacted_at: Simplefin::Normalizer.time(source["transacted_at"], fetched_at: fetched_at, optional: true),
          pending: source["pending"] == true
        }
        digest = Platform::Operations::RequestDigest.for(attributes)
        record = mapping.provider_transactions.find_or_initialize_by(provider_id: Simplefin::Normalizer.identity(source["id"]))
        next if record.persisted? && record.content_digest == digest
        if record.persisted?
          record.previous_revisions += [ record.attributes.slice("amount", "description", "posted_at", "transacted_at", "pending", "content_digest", "state") ]
          record.state = record.financial_transaction_id ? "changed" : "review"
        end
        record.assign_attributes(attributes.merge(budget_workspace: workspace, content_digest: digest, fetched_at: fetched_at))
        record.save!
      end
    end

    def mark_completed!(outcomes, errors)
      state = errors.any? || outcomes.values.any? { |value| value["state"] != "updated" } ? "partial" : "succeeded"
      refresh.update!(state: state, results: refresh.results.merge("accounts" => outcomes), provider_errors: errors, completed_at: Time.current, lease_expires_at: nil)
      connection.update!(last_checked_at: Time.current, next_refresh_at: 12.hours.from_now + rand(30).minutes,
        error_message: errors.map { |error| error["message"] }.join(" ").presence)
      connection.update!(status: "needs_attention", automatic_refresh: false) if errors.any? { |error| error["code"] == "gen.auth" }
      if errors.any? { |error| error["message"].to_s.match?(/quota|rate.?limit|too many requests/i) }
        connection.update!(automatic_refresh: false, next_refresh_at: 24.hours.from_now)
      end
      refresh.operation_run.update!(state: "succeeded", completed_at: Time.current, progress_current: 1, progress_total: 1,
        progress_label: state == "partial" ? "Checked with account warnings" : "SimpleFIN check complete",
        result_counts: { "accounts" => outcomes.size }, result_reference: { "type" => "BankRefresh", "id" => refresh.id })
    end

    def fail_attempt!(error)
      connection.with_lock do
        return if refresh.reload.terminal?
        return finish_cancelled! unless connection.credential_generation == refresh.credential_generation && workspace.reload.bank_sync_epoch == refresh.workspace_epoch
        return if lease && refresh.lease_token != lease
        retrying = error.retryable? && refresh.attempts < MAX_ATTEMPTS
        refresh.update!(state: retrying ? "pending" : "failed", provider_errors: [ { "code" => error.code.to_s, "message" => error.message } ],
          completed_at: retrying ? nil : Time.current, lease_expires_at: nil)
        connection.update!(error_message: error.message, next_refresh_at: 24.hours.from_now)
        connection.update!(status: "needs_attention", automatic_refresh: false) if error.code.in?(%i[authentication payment])
        refresh.operation_run.update!(state: retrying ? "running" : "failed", completed_at: retrying ? nil : Time.current,
          error_code: error.code.to_s, progress_label: error.message, retryable: retrying)
      end
    end

    def finish_cancelled!
      return if refresh.reload.terminal?
      return if lease && refresh.lease_token != lease
      refresh.update!(state: "cancelled", completed_at: Time.current, lease_expires_at: nil)
      refresh.operation_run.update!(state: "failed", completed_at: Time.current, error_code: "connection_changed", retryable: false)
    end
  end
end
