class AddDurableBackupExports < ActiveRecord::Migration[8.1]
  def change
    create_table :backup_export_artifacts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :operation_run, type: :uuid, null: false
      t.references :data_transfer_run, type: :uuid, null: false
      t.string :generation_key, null: false
      t.text :encrypted_export_password
      t.text :encrypted_contents
      t.string :filename
      t.string :content_type, null: false, default: "application/json; charset=utf-8"
      t.string :state, null: false, default: "pending"
      t.datetime :expires_at, null: false
      t.datetime :ready_at
      t.datetime :failed_at
      t.datetime :expired_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index :operation_run_id, unique: true, name: "uidx_backup_export_artifacts_operation"
      t.index :data_transfer_run_id, unique: true, name: "uidx_backup_export_artifacts_transfer"
      t.index %i[user_id state expires_at], name: "index_backup_export_artifacts_on_owner_state"
      t.index :expires_at,
        where: "state IN ('ready', 'failed')",
        name: "index_backup_export_artifacts_on_expiration"
      t.index %i[id budget_workspace_id], unique: true, name: "uidx_backup_export_artifacts_id_workspace"
      t.check_constraint "state IN ('pending', 'ready', 'failed', 'expired')", name: "backup_export_artifacts_state_valid"
      t.check_constraint "(state = 'ready') = (ready_at IS NOT NULL)", name: "backup_export_artifacts_ready_coherent"
      t.check_constraint "(state = 'failed') = (failed_at IS NOT NULL)", name: "backup_export_artifacts_failed_coherent"
      t.check_constraint "(state = 'expired') = (expired_at IS NOT NULL)", name: "backup_export_artifacts_expired_coherent"
      t.check_constraint "state <> 'ready' OR (encrypted_contents IS NOT NULL AND filename IS NOT NULL)", name: "backup_export_artifacts_contents_coherent"
      t.check_constraint "expires_at > created_at", name: "backup_export_artifacts_expiration_valid"
      t.check_constraint "lock_version >= 0", name: "backup_export_artifacts_lock_version_nonnegative"
    end

    add_foreign_key :backup_export_artifacts,
      :operation_runs,
      column: %i[operation_run_id budget_workspace_id],
      primary_key: %i[id budget_workspace_id],
      name: "fk_backup_export_artifacts_operation_workspace"
    add_foreign_key :backup_export_artifacts,
      :data_transfer_runs,
      column: %i[data_transfer_run_id budget_workspace_id],
      primary_key: %i[id budget_workspace_id],
      name: "fk_backup_export_artifacts_transfer_workspace"
  end
end
