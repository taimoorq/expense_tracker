class AddLegacyIntegrityColumns < ActiveRecord::Migration[8.1]
  LOCKED_TABLES = %i[
    accounts
    account_snapshots
    account_activity_imports
    budget_months
    expense_entries
    pay_schedules
    subscriptions
    monthly_bills
    payment_plans
    credit_cards
  ].freeze

  def change
    LOCKED_TABLES.each do |table_name|
      add_column table_name, :lock_version, :integer, null: false, default: 0
    end

    add_column :account_activity_imports, :file_digest, :string
    add_column :account_activity_imports, :commit_idempotency_key, :string

    add_index :account_activity_imports,
      [ :user_id, :commit_idempotency_key ],
      unique: true,
      where: "commit_idempotency_key IS NOT NULL",
      name: "uidx_activity_imports_user_commit_key"
  end
end
