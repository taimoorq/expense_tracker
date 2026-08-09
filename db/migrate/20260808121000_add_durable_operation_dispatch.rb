class AddDurableOperationDispatch < ActiveRecord::Migration[8.1]
  def change
    add_operation_dispatch_metadata
    create_account_activity_import_drafts
  end

  private

  def add_operation_dispatch_metadata
    change_table :operation_runs, bulk: true do |t|
      t.string :job_class
      t.jsonb :job_arguments, null: false, default: []
      t.datetime :enqueued_at
      t.datetime :last_enqueue_attempt_at
    end

    add_index :operation_runs,
      %i[state enqueued_at last_enqueue_attempt_at],
      where: "job_class IS NOT NULL AND state = 'pending'",
      name: "index_operations_on_pending_dispatch"
    add_check_constraint :operation_runs,
      "jsonb_typeof(job_arguments) = 'array'",
      name: "operations_job_arguments_array"
    add_check_constraint :operation_runs,
      "job_class IS NOT NULL OR job_arguments = '[]'::jsonb",
      name: "operations_job_metadata_coherent"
    add_check_constraint :operation_runs,
      "enqueued_at IS NULL OR job_class IS NOT NULL",
      name: "operations_enqueue_state_coherent"
  end

  def create_account_activity_import_drafts
    create_table :account_activity_import_drafts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :operation_run, type: :uuid
      t.string :token_digest, null: false
      t.string :commit_idempotency_key, null: false
      t.string :file_digest, null: false
      t.integer :rows_count, null: false
      t.integer :imported_count, null: false
      t.integer :duplicate_count, null: false
      t.jsonb :preview_payload, null: false, default: {}
      t.string :state, null: false, default: "previewed"
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.datetime :failed_at
      t.datetime :expired_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index :token_digest, unique: true, name: "uidx_activity_import_drafts_token"
      t.index %i[user_id account_id state expires_at], name: "index_activity_import_drafts_on_owner_state"
      t.index :expires_at,
        where: "state IN ('previewed', 'failed')",
        name: "index_activity_import_drafts_on_expiration"
      t.index :operation_run_id,
        unique: true,
        where: "operation_run_id IS NOT NULL",
        name: "uidx_activity_import_drafts_operation"
      t.index %i[id budget_workspace_id], unique: true, name: "uidx_activity_import_drafts_id_workspace"
      t.check_constraint "token_digest ~ '^[0-9a-f]{64}$'", name: "activity_import_drafts_token_valid"
      t.check_constraint "file_digest ~ '^[0-9a-f]{64}$'", name: "activity_import_drafts_file_digest_valid"
      t.check_constraint "rows_count >= 0 AND imported_count >= 0 AND duplicate_count >= 0", name: "activity_import_drafts_counts_nonnegative"
      t.check_constraint "imported_count + duplicate_count <= rows_count", name: "activity_import_drafts_counts_bounded"
      t.check_constraint "jsonb_typeof(preview_payload) = 'object'", name: "activity_import_drafts_payload_object"
      t.check_constraint "state IN ('previewed', 'queued', 'consumed', 'failed', 'expired')", name: "activity_import_drafts_state_valid"
      t.check_constraint "(state = 'consumed') = (consumed_at IS NOT NULL)", name: "activity_import_drafts_consumed_coherent"
      t.check_constraint "(state = 'failed') = (failed_at IS NOT NULL)", name: "activity_import_drafts_failed_coherent"
      t.check_constraint "(state = 'expired') = (expired_at IS NOT NULL)", name: "activity_import_drafts_expired_coherent"
      t.check_constraint "expires_at > created_at", name: "activity_import_drafts_expiration_valid"
      t.check_constraint "lock_version >= 0", name: "activity_import_drafts_lock_version_nonnegative"
    end

    add_foreign_key :account_activity_import_drafts,
      :accounts,
      column: %i[account_id user_id],
      primary_key: %i[id user_id],
      name: "fk_activity_import_drafts_account_owner"
    add_foreign_key :account_activity_import_drafts,
      :accounts,
      column: %i[account_id budget_workspace_id],
      primary_key: %i[id budget_workspace_id],
      name: "fk_activity_import_drafts_account_workspace"
    add_foreign_key :account_activity_import_drafts,
      :operation_runs,
      column: %i[operation_run_id budget_workspace_id],
      primary_key: %i[id budget_workspace_id],
      name: "fk_activity_import_drafts_operation_workspace"
  end
end
