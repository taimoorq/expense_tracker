class AddTargetMigrationStateToWorkspaces < ActiveRecord::Migration[8.1]
  def change
    add_reference :budget_workspaces,
      :legacy_owner_user,
      type: :uuid,
      foreign_key: { to_table: :users },
      index: { unique: true }
    add_column :budget_workspaces, :target_writes_enabled, :boolean, null: false, default: false
    add_column :budget_workspaces, :target_reads_enabled, :boolean, null: false, default: false
    add_column :budget_workspaces, :target_backfill_version, :string
    add_column :budget_workspaces, :target_backfilled_at, :datetime

    add_check_constraint :budget_workspaces,
      "NOT target_reads_enabled OR target_writes_enabled",
      name: "workspaces_target_read_requires_write"
  end
end
