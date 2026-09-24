module Accounts
  class TrackedAccountRow
    attr_reader :summary, :account, :mapping, :bank_balance, :snapshot

    def initialize(summary:, evidence:)
      @summary = summary
      @account = summary.fetch(:account)
      @mapping = evidence&.fetch(:mapping)
      @bank_balance = evidence&.fetch(:balance)
      @snapshot = account.latest_snapshot
    end

    def balance_available?
      summary.fetch(:balance_available)
    end

    def snapshot_action?
      !balance_available? || snapshot.present?
    end

    def snapshot_label
      return "Add balance" unless snapshot

      balance_available? ? "Edit balance" : "Fix balance"
    end

    def primary_action
      return :connection if connection_issue?
      return :review if review_needed?
      :snapshot unless balance_available?
    end

    def bank_amount
      bank_balance.balance * mapping.sign_multiplier if bank_balance
    end

    def bank_reported_at
      bank_balance&.reported_at&.in_time_zone(mapping.budget_workspace.time_zone)
    end

    def account_metadata
      [ account.institution_name.presence, account.kind.humanize ].compact.join(" · ")
    end

    def account_flags
      [ ("Inactive" unless account.active?), ("Not in net worth" unless account.include_in_net_worth?) ].compact.join(" · ")
    end

    private

    def connection_issue?
      return false unless mapping
      return false if mapping.bank_connection.status == "disconnected" || mapping.state == "ignored"

      mapping.state == "missing" || mapping.error_message.present? ||
        mapping.bank_connection.status == "needs_attention" || mapping.bank_connection.error_message.present? ||
        (mapping.bank_connection.status == "active" && !mapping.bank_connection.connected?)
    end

    def review_needed?
      bank_balance && mapping.state != "ignored" &&
        (!mapping.use_bank_balance? || bank_balance.state != "accepted" || !balance_available?)
    end
  end
end
