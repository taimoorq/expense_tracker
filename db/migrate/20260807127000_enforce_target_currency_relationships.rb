class EnforceTargetCurrencyRelationships < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  CURRENCY_IDENTITIES = {
    accounts: "uidx_accounts_id_workspace_currency",
    budget_periods: "uidx_periods_id_workspace_currency",
    budget_items: "uidx_items_id_workspace_currency",
    financial_transactions: "uidx_transactions_id_workspace_currency"
  }.freeze

  def up
    add_check_constraint :accounts,
      "currency_code IS NULL OR currency_code ~ '^[A-Z]{3}$'",
      name: "accounts_currency_valid",
      validate: false,
      if_not_exists: true

    CURRENCY_IDENTITIES.each do |table_name, name|
      add_index table_name,
        %i[id budget_workspace_id currency_code],
        unique: true,
        algorithm: :concurrently,
        if_not_exists: true,
        name: name
    end

    add_index :accounts,
      "budget_workspace_id, lower(name)",
      unique: true,
      where: "budget_workspace_id IS NOT NULL AND archived_at IS NULL",
      algorithm: :concurrently,
      if_not_exists: true,
      name: "uidx_active_accounts_workspace_name"

    add_currency_foreign_key :planning_templates, :accounts, :source_account_id, "fk_templates_source_account_currency"
    add_currency_foreign_key :planning_templates, :accounts, :destination_account_id, "fk_templates_destination_account_currency"
    add_currency_foreign_key :budget_items, :budget_periods, :budget_period_id, "fk_items_period_currency"
    add_currency_foreign_key :budget_items, :accounts, :intended_source_account_id, "fk_items_source_account_currency"
    add_currency_foreign_key :budget_items, :accounts, :intended_destination_account_id, "fk_items_destination_account_currency"
    add_currency_foreign_key :account_postings, :financial_transactions, :financial_transaction_id, "fk_postings_transaction_currency"
    add_currency_foreign_key :account_postings, :accounts, :account_id, "fk_postings_account_currency"
    add_currency_foreign_key :budget_allocations, :budget_items, :budget_item_id, "fk_allocations_item_currency"
    add_currency_foreign_key :budget_allocations, :financial_transactions, :financial_transaction_id, "fk_allocations_transaction_currency"
    add_currency_foreign_key :balance_observations, :accounts, :account_id, "fk_observations_account_currency"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Target currency constraints are removed only by a forward contract migration"
  end

  private

  def add_currency_foreign_key(from_table, to_table, foreign_id, name)
    add_foreign_key from_table,
      to_table,
      column: [ foreign_id, :budget_workspace_id, :currency_code ],
      primary_key: %i[id budget_workspace_id currency_code],
      name: name
  end
end
