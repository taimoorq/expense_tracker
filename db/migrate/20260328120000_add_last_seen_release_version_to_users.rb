class AddLastSeenReleaseVersionToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :last_seen_release_version, :string
  end
end
