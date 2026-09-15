class AddAutomatedBackups < ActiveRecord::Migration[8.1]
  def change
    create_backup_schedules
    create_backup_archives
    add_backup_foreign_keys
  end

  private

  def create_backup_schedules
    create_table :backup_schedules, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      table.references :creator_membership, type: :uuid, null: false,
        foreign_key: { to_table: :workspace_memberships }
      table.string :state, null: false, default: "paused"
      table.string :cadence, null: false, default: "daily"
      table.string :time_zone, null: false, default: "UTC"
      table.integer :local_minute_of_day, null: false, default: 120
      table.integer :weekday
      table.integer :day_of_month
      table.integer :retention_count, null: false, default: 14
      table.datetime :next_run_at
      table.datetime :last_attempted_at
      table.datetime :last_succeeded_at
      table.datetime :last_failed_at
      table.string :last_error_code
      table.integer :lock_version, null: false, default: 0
      table.timestamps

      table.index :budget_workspace_id, unique: true, name: "uidx_backup_schedules_workspace"
      table.index %i[state next_run_at],
        where: "state = 'enabled'",
        name: "idx_backup_schedules_due"
      table.index %i[id budget_workspace_id], unique: true, name: "uidx_backup_schedules_id_workspace"
      table.check_constraint "state IN ('enabled', 'paused')", name: "backup_schedules_state_valid"
      table.check_constraint "cadence IN ('daily', 'weekly', 'monthly')", name: "backup_schedules_cadence_valid"
      table.check_constraint "local_minute_of_day BETWEEN 0 AND 1439", name: "backup_schedules_local_time_valid"
      table.check_constraint "retention_count BETWEEN 1 AND 365", name: "backup_schedules_retention_valid"
      table.check_constraint <<~SQL.squish, name: "backup_schedules_cadence_fields_coherent"
        (cadence = 'daily' AND weekday IS NULL AND day_of_month IS NULL)
        OR (cadence = 'weekly' AND weekday BETWEEN 0 AND 6 AND day_of_month IS NULL)
        OR (cadence = 'monthly' AND weekday IS NULL AND day_of_month BETWEEN 1 AND 28)
      SQL
      table.check_constraint "(state = 'enabled') = (next_run_at IS NOT NULL)",
        name: "backup_schedules_next_run_coherent"
      table.check_constraint "lock_version >= 0", name: "backup_schedules_lock_version_nonnegative"
    end
  end

  def create_backup_archives
    create_table :backup_archives, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      table.references :backup_schedule, type: :uuid, foreign_key: true
      table.references :actor_membership, type: :uuid, null: false,
        foreign_key: { to_table: :workspace_memberships }
      table.references :operation_run, type: :uuid, null: false
      table.references :data_transfer_run, type: :uuid, null: false
      table.string :trigger, null: false
      table.datetime :scheduled_for
      table.string :state, null: false, default: "pending"
      table.string :storage_adapter, null: false
      table.string :storage_key, null: false
      table.string :filename, null: false
      table.string :content_type, null: false, default: "application/json; charset=utf-8"
      table.string :payload_format_version, null: false, default: "2"
      table.string :envelope_version, null: false
      table.string :encryption_key_id, null: false
      table.string :payload_checksum
      table.string :archive_checksum
      table.bigint :byte_size
      table.string :error_code
      table.datetime :started_at
      table.datetime :stored_at
      table.datetime :verified_at
      table.datetime :failed_at
      table.datetime :deleting_at
      table.datetime :deleted_at
      table.integer :lock_version, null: false, default: 0
      table.timestamps

      table.index :operation_run_id, unique: true, name: "uidx_backup_archives_operation"
      table.index :data_transfer_run_id, unique: true, name: "uidx_backup_archives_transfer"
      table.index %i[backup_schedule_id scheduled_for], unique: true,
        where: "backup_schedule_id IS NOT NULL",
        name: "uidx_backup_archives_schedule_slot"
      table.index %i[storage_adapter storage_key], unique: true, name: "uidx_backup_archives_storage_effect"
      table.index %i[budget_workspace_id state created_at], name: "idx_backup_archives_workspace_state"
      table.index :budget_workspace_id, unique: true,
        where: "state IN ('pending', 'writing')",
        name: "uidx_backup_archives_active_workspace"
      table.index %i[id budget_workspace_id], unique: true, name: "uidx_backup_archives_id_workspace"
      table.check_constraint "trigger IN ('manual', 'scheduled')", name: "backup_archives_trigger_valid"
      table.check_constraint <<~SQL.squish, name: "backup_archives_schedule_slot_coherent"
        (trigger = 'manual' AND backup_schedule_id IS NULL AND scheduled_for IS NULL)
        OR (trigger = 'scheduled' AND backup_schedule_id IS NOT NULL AND scheduled_for IS NOT NULL)
      SQL
      table.check_constraint "state IN ('pending', 'writing', 'ready', 'failed', 'deleting', 'deleted')",
        name: "backup_archives_state_valid"
      table.check_constraint "payload_checksum IS NULL OR payload_checksum ~ '^[0-9a-f]{64}$'",
        name: "backup_archives_payload_checksum_valid"
      table.check_constraint "archive_checksum IS NULL OR archive_checksum ~ '^[0-9a-f]{64}$'",
        name: "backup_archives_archive_checksum_valid"
      table.check_constraint "byte_size IS NULL OR byte_size >= 0", name: "backup_archives_byte_size_nonnegative"
      table.check_constraint "(state = 'ready') = (verified_at IS NOT NULL)", name: "backup_archives_ready_coherent"
      table.check_constraint "(state = 'failed') = (failed_at IS NOT NULL)", name: "backup_archives_failed_coherent"
      table.check_constraint "(state = 'deleting') = (deleting_at IS NOT NULL)", name: "backup_archives_deleting_coherent"
      table.check_constraint "(state = 'deleted') = (deleted_at IS NOT NULL)", name: "backup_archives_deleted_coherent"
      table.check_constraint <<~SQL.squish, name: "backup_archives_stored_metadata_coherent"
        state NOT IN ('ready', 'deleting', 'deleted')
        OR (stored_at IS NOT NULL AND payload_checksum IS NOT NULL AND archive_checksum IS NOT NULL AND byte_size IS NOT NULL)
      SQL
      table.check_constraint "lock_version >= 0", name: "backup_archives_lock_version_nonnegative"
    end
  end

  def add_backup_foreign_keys
    add_foreign_key :backup_schedules, :workspace_memberships,
      column: %i[creator_membership_id budget_workspace_id],
      primary_key: %i[id budget_workspace_id],
      name: "fk_backup_schedules_creator_workspace"
    add_foreign_key :backup_archives, :workspace_memberships,
      column: %i[actor_membership_id budget_workspace_id],
      primary_key: %i[id budget_workspace_id],
      name: "fk_backup_archives_actor_workspace"
    add_foreign_key :backup_archives, :backup_schedules,
      column: %i[backup_schedule_id budget_workspace_id],
      primary_key: %i[id budget_workspace_id],
      name: "fk_backup_archives_schedule_workspace"
    add_foreign_key :backup_archives, :operation_runs,
      column: %i[operation_run_id budget_workspace_id],
      primary_key: %i[id budget_workspace_id],
      name: "fk_backup_archives_operation_workspace"
    add_foreign_key :backup_archives, :data_transfer_runs,
      column: %i[data_transfer_run_id budget_workspace_id],
      primary_key: %i[id budget_workspace_id],
      name: "fk_backup_archives_transfer_workspace"
  end
end
