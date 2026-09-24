class AddBankReconciliationEvidence < ActiveRecord::Migration[8.1]
  def change
    add_reference :payment_commitments, :excluded_provider_balance, type: :uuid, foreign_key: { to_table: :provider_balances }
    add_foreign_key :payment_commitments, :provider_balances, column: [ :excluded_provider_balance_id, :budget_workspace_id ], primary_key: [ :id, :budget_workspace_id ]
    add_column :balance_observations, :transaction_coverage, :jsonb, null: false, default: {}
    add_column :account_postings, :effective_at, :datetime, precision: 6
    add_index :balance_observations, :provider_balance_id, unique: true, where: "provider_balance_id IS NOT NULL", name: "one_observation_per_provider_balance"
  end
end
