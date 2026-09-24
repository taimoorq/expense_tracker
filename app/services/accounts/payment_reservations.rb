module Accounts
  class PaymentReservations
    def self.ensure_for!(entry)
      existing = entry.payment_commitments.find_by(state: "reserved")
      if existing
        changed = entry.previous_changes.keys & %w[status actual_amount occurred_on occurred_at source_account_id destination_account_id]
        return if changed.empty?
        if existing.payment_settlements.exists?
          raise Platform::TargetSync::WriteRejected, "Undo the linked bank activity before changing this recorded payment."
        end
        unless entry.paid?
          existing.update!(state: "cancelled")
          return
        end
        unless entry.source_account_id == existing.account_id
          raise Platform::TargetSync::WriteRejected, "Return this payment to Planned before changing its funding account."
        end
        existing.update!(amount: entry.actual_amount, initiated_on: entry.occurred_on, initiated_at: entry.occurred_at,
          destination_account: entry.destination_account, included_provider_balance: nil, excluded_provider_balance: nil)
        return existing
      end
      return unless entry.paid? && !entry.income? && entry.source_account&.connected_account
      mapping = entry.source_account.connected_account
      return unless mapping.use_bank_balance? || mapping.bank_connection.connected?
      return if entry.account_activities.exists?
      return unless (entry.previous_changes.keys & %w[status actual_amount created_at]).any?
      return if entry.provider_transactions.where(state: %w[accepted changed]).exists?
      return if entry.payment_commitments.where(state: "settled").exists?
      entry.payment_commitments.create!(budget_workspace: entry.budget_workspace, account: entry.source_account,
        destination_account: entry.destination_account, amount: entry.actual_amount, currency_code: entry.source_account.currency_code,
        initiated_on: entry.occurred_on, initiated_at: entry.occurred_at, reserved_at: Time.current)
    end
  end
end
