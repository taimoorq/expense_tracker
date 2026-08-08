class AddLegacyOwnershipConstraints < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  PARENT_INDEXES = [
    [ :accounts, [ :id, :user_id ], "uidx_accounts_id_user" ],
    [ :budget_months, [ :id, :user_id ], "uidx_budget_months_id_user" ],
    [ :expense_entries, [ :id, :user_id ], "uidx_expense_entries_id_user" ],
    [ :account_activity_imports, [ :id, :user_id, :account_id ], "uidx_activity_imports_id_user_account" ]
  ].freeze

  FOREIGN_KEYS = [
    [ :expense_entries, :budget_months, [ :budget_month_id, :user_id ], [ :id, :user_id ], "fk_entries_month_owner" ],
    [ :expense_entries, :accounts, [ :source_account_id, :user_id ], [ :id, :user_id ], "fk_entries_source_account_owner" ],
    [ :expense_entries, :accounts, [ :destination_account_id, :user_id ], [ :id, :user_id ], "fk_entries_destination_account_owner" ],
    [ :account_activity_imports, :accounts, [ :account_id, :user_id ], [ :id, :user_id ], "fk_activity_imports_account_owner" ],
    [ :account_activities, :accounts, [ :account_id, :user_id ], [ :id, :user_id ], "fk_activities_account_owner" ],
    [ :account_activities, :account_activity_imports, [ :account_activity_import_id, :user_id, :account_id ], [ :id, :user_id, :account_id ], "fk_activities_import_scope" ],
    [ :account_activities, :expense_entries, [ :expense_entry_id, :user_id ], [ :id, :user_id ], "fk_activities_entry_owner" ],
    [ :pay_schedules, :accounts, [ :linked_account_id, :user_id ], [ :id, :user_id ], "fk_pay_schedules_account_owner" ],
    [ :subscriptions, :accounts, [ :linked_account_id, :user_id ], [ :id, :user_id ], "fk_subscriptions_account_owner" ],
    [ :monthly_bills, :accounts, [ :linked_account_id, :user_id ], [ :id, :user_id ], "fk_monthly_bills_account_owner" ],
    [ :payment_plans, :accounts, [ :linked_account_id, :user_id ], [ :id, :user_id ], "fk_payment_plans_account_owner" ],
    [ :credit_cards, :accounts, [ :linked_account_id, :user_id ], [ :id, :user_id ], "fk_credit_cards_linked_account_owner" ],
    [ :credit_cards, :accounts, [ :payment_account_id, :user_id ], [ :id, :user_id ], "fk_credit_cards_payment_account_owner" ]
  ].freeze

  def up
    PARENT_INDEXES.each do |table_name, columns, name|
      add_index table_name,
        columns,
        unique: true,
        algorithm: :concurrently,
        if_not_exists: true,
        name: name
    end

    FOREIGN_KEYS.each do |from_table, to_table, columns, primary_keys, name|
      add_foreign_key from_table,
        to_table,
        column: columns,
        primary_key: primary_keys,
        name: name,
        validate: false,
        if_not_exists: true
    end
  end

  def down
    FOREIGN_KEYS.reverse_each do |from_table, to_table, _columns, _primary_keys, name|
      remove_foreign_key from_table, to_table, name: name, if_exists: true
    end

    PARENT_INDEXES.reverse_each do |table_name, _columns, name|
      remove_index table_name, name: name, algorithm: :concurrently, if_exists: true
    end
  end
end
