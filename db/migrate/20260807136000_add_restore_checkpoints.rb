class AddRestoreCheckpoints < ActiveRecord::Migration[8.1]
  AUDIT_ACTIONS = %w[
    create edit void reverse archive import import_reversal match unmatch generate
    trust_observation supersede_observation close reopen backup_export backup_restore
    access_change resolve_migration_discrepancy restore_checkpoint restore_rollback
  ].freeze

  def up
    create_table :restore_checkpoints, id: :uuid do |table|
      table.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      table.references :actor_membership, type: :uuid, foreign_key: { to_table: :workspace_memberships }
      table.references :checkpoint_operation, type: :uuid, foreign_key: { to_table: :operation_runs }
      table.string :state, null: false, default: "ready"
      table.string :payload_format_version, null: false
      table.string :payload_checksum, null: false
      table.string :encryption_version, null: false, default: "app-key-v1"
      table.jsonb :selected_scopes, null: false, default: []
      table.jsonb :result_counts, null: false, default: {}
      table.text :encrypted_payload, null: false
      table.datetime :expires_at, null: false
      table.datetime :restored_at
      table.integer :lock_version, null: false, default: 0
      table.timestamps

      table.index %i[budget_workspace_id state created_at], name: "idx_restore_checkpoints_workspace_state"
      table.index %i[id budget_workspace_id], unique: true, name: "uidx_restore_checkpoints_id_workspace"
      table.check_constraint "state IN ('ready', 'restored', 'expired')", name: "restore_checkpoints_state_valid"
      table.check_constraint "payload_checksum ~ '^[0-9a-f]{64}$'", name: "restore_checkpoints_checksum_valid"
      table.check_constraint "(state = 'restored') = (restored_at IS NOT NULL)", name: "restore_checkpoints_restored_at_coherent"
      table.check_constraint "lock_version >= 0", name: "restore_checkpoints_lock_version_nonnegative"
    end

    add_foreign_key :restore_checkpoints, :workspace_memberships,
      column: %i[actor_membership_id budget_workspace_id],
      primary_key: %i[id budget_workspace_id],
      name: "fk_restore_checkpoints_membership_workspace"
    add_foreign_key :restore_checkpoints, :operation_runs,
      column: %i[checkpoint_operation_id budget_workspace_id],
      primary_key: %i[id budget_workspace_id],
      name: "fk_restore_checkpoints_operation_workspace"

    remove_check_constraint :audit_events, name: "audit_events_action_valid"
    add_check_constraint :audit_events,
      "action IN (#{AUDIT_ACTIONS.map { |action| connection.quote(action) }.join(', ')})",
      name: "audit_events_action_valid"
  end

  def down
    drop_table :restore_checkpoints
    remove_check_constraint :audit_events, name: "audit_events_action_valid"
    prior_actions = AUDIT_ACTIONS - %w[restore_checkpoint restore_rollback]
    add_check_constraint :audit_events,
      "action IN (#{prior_actions.map { |action| connection.quote(action) }.join(', ')})",
      name: "audit_events_action_valid"
  end
end
