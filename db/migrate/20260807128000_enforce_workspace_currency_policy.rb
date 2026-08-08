class EnforceWorkspaceCurrencyPolicy < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  CURRENCY_TABLES = %i[
    accounts
    budget_periods
    planning_templates
    budget_items
    financial_transactions
    account_postings
    budget_allocations
    balance_observations
  ].freeze

  def up
    add_index :budget_workspaces,
      %i[id default_currency_code],
      unique: true,
      algorithm: :concurrently,
      name: "uidx_workspaces_id_currency"

    CURRENCY_TABLES.each do |table_name|
      add_foreign_key table_name,
        :budget_workspaces,
        column: %i[budget_workspace_id currency_code],
        primary_key: %i[id default_currency_code],
        name: "fk_#{table_name}_workspace_currency"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Workspace currency enforcement is removed only by a forward migration"
  end
end
