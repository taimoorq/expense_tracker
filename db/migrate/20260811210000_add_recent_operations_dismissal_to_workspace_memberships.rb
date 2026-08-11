class AddRecentOperationsDismissalToWorkspaceMemberships < ActiveRecord::Migration[8.1]
  def change
    add_column :workspace_memberships, :recent_operations_dismissed_through_at, :datetime
  end
end
