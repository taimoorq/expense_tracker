class AddTellerFieldsToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :teller_account_id, :string
    add_column :accounts, :teller_enrollment_id, :string
    add_column :accounts, :teller_access_token, :text
    add_column :accounts, :teller_sync_enabled, :boolean, default: false, null: false
    add_column :accounts, :teller_last_synced_at, :datetime

    add_index :accounts, :teller_account_id
    add_index :accounts, :teller_enrollment_id
    add_index :accounts, :teller_sync_enabled
  end
end
