class FinalizeBankEvidenceConstraints < ActiveRecord::Migration[8.1]
  def change
    rename_column :bank_refreshes, :errors, :provider_errors
    add_index :expense_entries, [ :id, :budget_workspace_id ], unique: true
    [ :provider_transactions, :payment_commitments ].each do |table|
      add_foreign_key table, :expense_entries, column: [ :expense_entry_id, :budget_workspace_id ], primary_key: [ :id, :budget_workspace_id ]
    end
    add_check_constraint :provider_transactions, "amount <> 0 AND (pending OR posted_at IS NOT NULL)", name: "provider_transactions_valid_movement"
    add_check_constraint :connected_accounts, "NOT use_bank_balance OR account_id IS NOT NULL", name: "bank_source_requires_mapping"
  end
end
