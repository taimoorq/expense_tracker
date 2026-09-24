module Platform
  module Backup
    module V2
      # Portable evidence only. Credentials, leases and scheduled refreshes never
      # cross a backup boundary; restored connections always require reconnecting.
      class BankData
        DEFINITIONS = {
          bank_connection: [ BankConnection, %w[name created_at updated_at], {} ],
          connected_account: [ ConnectedAccount, %w[provider_connection_id provider_account_id name institution_name currency state sign_multiplier mapping_version use_bank_balance import_transactions last_seen_at last_checked_at transactions_through_at created_at updated_at], { bank_connection: :bank_connection, account: :account } ],
          provider_balance: [ ProviderBalance, %w[balance available_balance currency content_digest reported_at fetched_at state created_at updated_at], { connected_account: :connected_account } ],
          provider_transaction: [ ProviderTransaction, %w[provider_id content_digest currency description amount transacted_at posted_at pending state resolution_kind previous_revisions fetched_at created_at updated_at], { connected_account: :connected_account, financial_transaction: :transaction } ],
          payment_commitment: [ PaymentCommitment, %w[amount currency_code initiated_on initiated_at reserved_at state created_at updated_at], { account: :account, destination_account: :account, included_provider_balance: :provider_balance, excluded_provider_balance: :provider_balance } ],
          payment_settlement: [ PaymentSettlement, %w[amount created_at updated_at], { payment_commitment: :payment_commitment, financial_transaction: :transaction } ]
        }.freeze

        def self.export(workspace)
          entry_items = workspace.legacy_record_mappings.status_mapped.where(legacy_record_type: "ExpenseEntry", target_record_type: "BudgetItem").pluck(:legacy_record_id, :target_record_id).to_h
          DEFINITIONS.to_h do |type, (model, fields, references)|
            rows = model.where(budget_workspace: workspace).order(:created_at, :id).map do |record|
              refs = references.to_h { |association, _| [ "#{association}_external_id", record.public_send("#{association}_id") ] }.compact
              if record.respond_to?(:expense_entry_id) && record.expense_entry_id
                refs["budget_item_external_id"] = entry_items.fetch(record.expense_entry_id)
              end
              { external_id: record.id, attributes: Platform::CanonicalJson.normalize(record.attributes.slice(*fields)) }.merge(refs)
            end
            [ type, rows ]
          end
        end

        def initialize(data:, workspace:, membership:, lookup:, register:)
          @data, @workspace, @membership, @lookup, @register = data || {}, workspace, membership, lookup, register
        end

        def restore!
          DEFINITIONS.each do |type, (model, fields, references)|
            Array(@data[type]).each do |record|
              values = record.fetch(:attributes).stringify_keys.slice(*fields)
              references.each do |association, target_type|
                id = record["#{association}_external_id".to_sym]
                values[association] = @lookup.call(target_type, id) if id.present?
              end
              if type == :bank_connection
                values.merge!(actor_membership: @membership, status: "disconnected", claim_fingerprint: SecureRandom.hex(32), automatic_refresh: false)
              end
              row = model.create!(values.merge(budget_workspace: @workspace))
              @register.call(type, record, row)
            end
          end
        end

        def restore_entry_links!
          %i[provider_transaction payment_commitment].each do |type|
            Array(@data[type]).each do |record|
              next if record[:budget_item_external_id].blank?
              item = @lookup.call(:item, record[:budget_item_external_id])
              mapping = @workspace.legacy_record_mappings.status_mapped.find_by!(target_record_type: "BudgetItem", target_record_id: item.id, legacy_record_type: "ExpenseEntry")
              @lookup.call(type, record[:external_id]).update!(expense_entry_id: mapping.legacy_record_id)
            end
          end
        end
      end
    end
  end
end
