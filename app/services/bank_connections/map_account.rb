module BankConnections
  class MapAccount
    def self.call(mapping:, membership:, account_id: nil, name: nil, kind: nil, ignore: false, sign_multiplier: 1, import_transactions: false)
      workspace = mapping.budget_workspace
      Access.authorize!(workspace: workspace, membership: membership)
      mapping.bank_connection.with_lock do
        mapping.reload
        raise ArgumentError, "This account uses an unsupported currency." unless mapping.supported_currency?
        if ignore
          mapping.update!(state: "ignored", use_bank_balance: false, import_transactions: false, mapping_version: mapping.mapping_version + 1)
          return mapping
        end
        account = if account_id.present?
          workspace.accounts.where(user_id: membership.user_id).find(account_id)
        elsif mapping.account
          mapping.account
        else
          workspace.accounts.create!(user: membership.user, name: name.presence || mapping.name, kind: kind,
            institution_name: mapping.institution_name, currency_code: mapping.currency)
        end
        if mapping.account_id && (mapping.account_id != account.id || mapping.sign_multiplier != sign_multiplier.to_i) &&
            (mapping.provider_transactions.where.not(financial_transaction_id: nil).exists? || mapping.provider_balances.where(state: "accepted").exists?)
          raise ArgumentError, "This mapping has accepted history. Keep its account and balance interpretation; disconnect to stop future updates."
        end
        mapping.update!(account: account, sign_multiplier: sign_multiplier.to_i, state: "mapped",
          import_transactions: import_transactions, mapping_version: mapping.mapping_version + 1)
        mapping
      end
    end
  end
end
