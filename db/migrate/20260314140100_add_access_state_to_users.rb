class AddAccessStateToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :access_state, :integer, null: false, default: 0
    add_index :users, :access_state
  end
end