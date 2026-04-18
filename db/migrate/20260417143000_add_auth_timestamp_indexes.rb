class AddAuthTimestampIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :admin_users, :remember_created_at, if_not_exists: true
    add_index :users, :remember_created_at, if_not_exists: true
    add_index :users, :reset_password_sent_at, if_not_exists: true
  end
end
