class AddPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :default_landing_page, :string, null: false, default: "overview"
    add_column :users, :preferred_month_view, :string, null: false, default: "timeline"
  end
end
