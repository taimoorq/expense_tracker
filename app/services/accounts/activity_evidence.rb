module Accounts
  # Exactly one representation of each accepted movement feeds suggestions and
  # insights. Compatibility rows remain the input until ledger read cutover.
  class ActivityEvidence
    Row = Data.define(:id, :transaction_on, :description, :amount, :account_delta,
      :category, :activity_type, :memo, :fingerprint, :source_label, :detail_path)

    def self.call(account:)
      return account.account_activities.recent_first.to_a unless account.budget_workspace&.target_reads_enabled?

      workspace = account.budget_workspace
      account.account_postings.joins(:financial_transaction).where(financial_transactions: { state: "posted" })
        .includes(financial_transaction: [ :category, :provider_transactions, :import_row ]).map do |posting|
          transaction = posting.financial_transaction
          date = posting.effective_at&.in_time_zone(workspace.time_zone)&.to_date || transaction.effective_on
          Row.new(id: posting.id, transaction_on: date, description: transaction.description,
            amount: posting.amount.abs, account_delta: posting.amount, category: transaction.category&.name || transaction.import_row&.normalized_payload&.fetch("category", nil),
            activity_type: transaction.flow_kind_transfer? ? "Transfer" : transaction.import_row&.normalized_payload&.fetch("activity_type", nil), memo: transaction.memo,
            fingerprint: transaction.import_row&.fingerprint || "ledger:#{transaction.id}:#{posting.id}", source_label: Activity::SourceLabel.call(transaction),
            detail_path: Rails.application.routes.url_helpers.activity_path(view: "all", transaction_id: transaction.id))
        end.sort_by { |row| [ row.transaction_on, row.id ] }.reverse
    end
  end
end
