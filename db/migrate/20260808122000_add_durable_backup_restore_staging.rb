class AddDurableBackupRestoreStaging < ActiveRecord::Migration[8.1]
  def change
    create_table :backup_restore_drafts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :operation_run, type: :uuid
      t.references :data_transfer_run, type: :uuid
      t.references :restore_checkpoint, type: :uuid
      t.string :token_digest, null: false
      t.string :payload_checksum, null: false
      t.string :payload_format_version, null: false
      t.text :encrypted_payload, null: false
      t.jsonb :selected_scopes, null: false, default: []
      t.jsonb :validation_manifest, null: false, default: {}
      t.boolean :source_encrypted, null: false, default: false
      t.boolean :replacement_requested, null: false, default: false
      t.string :state, null: false, default: "previewed"
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.datetime :failed_at
      t.datetime :expired_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index :token_digest, unique: true, name: "uidx_backup_restore_drafts_token"
      t.index %i[user_id state expires_at], name: "index_backup_restore_drafts_on_owner_state"
      t.index :expires_at,
        where: "state IN ('previewed', 'failed')",
        name: "index_backup_restore_drafts_on_expiration"
      t.index :operation_run_id, unique: true, where: "operation_run_id IS NOT NULL", name: "uidx_backup_restore_drafts_operation"
      t.index :data_transfer_run_id, unique: true, where: "data_transfer_run_id IS NOT NULL", name: "uidx_backup_restore_drafts_transfer"
      t.index %i[id budget_workspace_id], unique: true, name: "uidx_backup_restore_drafts_id_workspace"
      t.check_constraint "token_digest ~ '^[0-9a-f]{64}$'", name: "backup_restore_drafts_token_valid"
      t.check_constraint "payload_checksum ~ '^[0-9a-f]{64}$'", name: "backup_restore_drafts_checksum_valid"
      t.check_constraint "jsonb_typeof(selected_scopes) = 'array'", name: "backup_restore_drafts_scopes_array"
      t.check_constraint "jsonb_typeof(validation_manifest) = 'object'", name: "backup_restore_drafts_manifest_object"
      t.check_constraint "state IN ('previewed', 'queued', 'consumed', 'failed', 'expired')", name: "backup_restore_drafts_state_valid"
      t.check_constraint "(state = 'consumed') = (consumed_at IS NOT NULL)", name: "backup_restore_drafts_consumed_coherent"
      t.check_constraint "(state = 'failed') = (failed_at IS NOT NULL)", name: "backup_restore_drafts_failed_coherent"
      t.check_constraint "(state = 'expired') = (expired_at IS NOT NULL)", name: "backup_restore_drafts_expired_coherent"
      t.check_constraint "expires_at > created_at", name: "backup_restore_drafts_expiration_valid"
      t.check_constraint "lock_version >= 0", name: "backup_restore_drafts_lock_version_nonnegative"
    end

    add_foreign_key :backup_restore_drafts,
      :operation_runs,
      column: %i[operation_run_id budget_workspace_id],
      primary_key: %i[id budget_workspace_id],
      name: "fk_backup_restore_drafts_operation_workspace"
    add_foreign_key :backup_restore_drafts,
      :data_transfer_runs,
      column: %i[data_transfer_run_id budget_workspace_id],
      primary_key: %i[id budget_workspace_id],
      name: "fk_backup_restore_drafts_transfer_workspace"
    add_foreign_key :backup_restore_drafts,
      :restore_checkpoints,
      column: %i[restore_checkpoint_id budget_workspace_id],
      primary_key: %i[id budget_workspace_id],
      name: "fk_backup_restore_drafts_checkpoint_workspace"
  end
end
