# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_11_210000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "account_activities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_activity_import_id", null: false
    t.decimal "account_delta", precision: 14, scale: 2, null: false
    t.uuid "account_id", null: false
    t.string "activity_type"
    t.decimal "amount", precision: 14, scale: 2, null: false
    t.uuid "budget_workspace_id"
    t.string "category"
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.uuid "expense_entry_id"
    t.string "fingerprint", null: false
    t.text "memo"
    t.date "posted_on"
    t.decimal "raw_amount", precision: 14, scale: 2, null: false
    t.jsonb "raw_payload", default: {}, null: false
    t.integer "row_number", null: false
    t.date "transaction_on", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["account_activity_import_id"], name: "index_account_activities_on_import_id"
    t.index ["account_id", "fingerprint"], name: "index_account_activities_on_account_id_and_fingerprint", unique: true
    t.index ["account_id", "transaction_on", "created_at"], name: "index_account_activities_on_account_chronological", order: { transaction_on: :desc, created_at: :desc }
    t.index ["account_id"], name: "index_account_activities_on_account_id"
    t.index ["budget_workspace_id"], name: "index_account_activities_on_budget_workspace_id"
    t.index ["expense_entry_id"], name: "index_account_activities_on_expense_entry_id"
    t.index ["user_id", "account_id", "activity_type"], name: "index_account_activities_on_user_account_activity_type"
    t.index ["user_id", "account_id", "category"], name: "index_account_activities_on_user_account_category"
    t.index ["user_id"], name: "index_account_activities_on_user_id"
    t.check_constraint "amount >= 0::numeric", name: "account_activities_amount_nonnegative"
    t.check_constraint "row_number >= 1", name: "account_activities_row_number_positive"
  end

  create_table "account_activity_import_drafts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "budget_workspace_id", null: false
    t.string "commit_idempotency_key", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.integer "duplicate_count", null: false
    t.datetime "expired_at"
    t.datetime "expires_at", null: false
    t.datetime "failed_at"
    t.string "file_digest", null: false
    t.integer "imported_count", null: false
    t.integer "lock_version", default: 0, null: false
    t.uuid "operation_run_id"
    t.jsonb "preview_payload", default: {}, null: false
    t.integer "rows_count", null: false
    t.string "state", default: "previewed", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["account_id"], name: "index_account_activity_import_drafts_on_account_id"
    t.index ["budget_workspace_id"], name: "index_account_activity_import_drafts_on_budget_workspace_id"
    t.index ["expires_at"], name: "index_activity_import_drafts_on_expiration", where: "((state)::text = ANY ((ARRAY['previewed'::character varying, 'failed'::character varying])::text[]))"
    t.index ["id", "budget_workspace_id"], name: "uidx_activity_import_drafts_id_workspace", unique: true
    t.index ["operation_run_id"], name: "index_account_activity_import_drafts_on_operation_run_id"
    t.index ["operation_run_id"], name: "uidx_activity_import_drafts_operation", unique: true, where: "(operation_run_id IS NOT NULL)"
    t.index ["token_digest"], name: "uidx_activity_import_drafts_token", unique: true
    t.index ["user_id", "account_id", "state", "expires_at"], name: "index_activity_import_drafts_on_owner_state"
    t.index ["user_id"], name: "index_account_activity_import_drafts_on_user_id"
    t.check_constraint "(imported_count + duplicate_count) <= rows_count", name: "activity_import_drafts_counts_bounded"
    t.check_constraint "(state::text = 'consumed'::text) = (consumed_at IS NOT NULL)", name: "activity_import_drafts_consumed_coherent"
    t.check_constraint "(state::text = 'expired'::text) = (expired_at IS NOT NULL)", name: "activity_import_drafts_expired_coherent"
    t.check_constraint "(state::text = 'failed'::text) = (failed_at IS NOT NULL)", name: "activity_import_drafts_failed_coherent"
    t.check_constraint "expires_at > created_at", name: "activity_import_drafts_expiration_valid"
    t.check_constraint "file_digest::text ~ '^[0-9a-f]{64}$'::text", name: "activity_import_drafts_file_digest_valid"
    t.check_constraint "jsonb_typeof(preview_payload) = 'object'::text", name: "activity_import_drafts_payload_object"
    t.check_constraint "lock_version >= 0", name: "activity_import_drafts_lock_version_nonnegative"
    t.check_constraint "rows_count >= 0 AND imported_count >= 0 AND duplicate_count >= 0", name: "activity_import_drafts_counts_nonnegative"
    t.check_constraint "state::text = ANY (ARRAY['previewed'::character varying, 'queued'::character varying, 'consumed'::character varying, 'failed'::character varying, 'expired'::character varying]::text[])", name: "activity_import_drafts_state_valid"
    t.check_constraint "token_digest::text ~ '^[0-9a-f]{64}$'::text", name: "activity_import_drafts_token_valid"
  end

  create_table "account_activity_imports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "amount_strategy", null: false
    t.uuid "budget_workspace_id"
    t.jsonb "column_mapping", default: {}, null: false
    t.string "commit_idempotency_key"
    t.datetime "created_at", null: false
    t.integer "duplicate_count", default: 0, null: false
    t.date "ended_on"
    t.string "file_digest"
    t.integer "header_row_number", null: false
    t.integer "imported_count", default: 0, null: false
    t.integer "lock_version", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "original_filename", null: false
    t.integer "rows_count", default: 0, null: false
    t.date "started_on"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.jsonb "warning_messages", default: [], null: false
    t.index ["account_id", "created_at"], name: "index_account_activity_imports_on_account_recent", order: { created_at: :desc }
    t.index ["account_id"], name: "index_account_activity_imports_on_account_id"
    t.index ["budget_workspace_id"], name: "index_account_activity_imports_on_budget_workspace_id"
    t.index ["id", "user_id", "account_id"], name: "uidx_activity_imports_id_user_account", unique: true
    t.index ["user_id", "account_id", "created_at"], name: "index_account_activity_imports_on_user_account_recent", order: { created_at: :desc }
    t.index ["user_id", "commit_idempotency_key"], name: "uidx_activity_imports_user_commit_key", unique: true, where: "(commit_idempotency_key IS NOT NULL)"
    t.index ["user_id"], name: "index_account_activity_imports_on_user_id"
    t.check_constraint "(imported_count + duplicate_count) <= rows_count", name: "activity_imports_counts_coherent"
    t.check_constraint "amount_strategy::text = ANY (ARRAY['charges_are_negative'::character varying, 'charges_are_positive'::character varying, 'type_column'::character varying]::text[])", name: "activity_imports_amount_strategy_valid"
    t.check_constraint "commit_idempotency_key IS NULL OR commit_idempotency_key::text ~ '^[0-9a-f]{64}$'::text", name: "activity_imports_commit_key_valid"
    t.check_constraint "file_digest IS NULL OR file_digest::text ~ '^[0-9a-f]{64}$'::text", name: "activity_imports_file_digest_valid"
    t.check_constraint "header_row_number >= 1", name: "activity_imports_header_row_positive"
    t.check_constraint "lock_version >= 0", name: "activity_imports_lock_version_nonnegative"
    t.check_constraint "rows_count >= 0 AND imported_count >= 0 AND duplicate_count >= 0", name: "activity_imports_counts_nonnegative"
    t.check_constraint "started_on IS NULL OR ended_on IS NULL OR ended_on >= started_on", name: "activity_imports_date_window_valid"
  end

  create_table "account_postings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "amount", precision: 19, scale: 4, null: false
    t.uuid "budget_workspace_id", null: false
    t.datetime "created_at", null: false
    t.string "currency_code", limit: 3, null: false
    t.uuid "financial_transaction_id", null: false
    t.string "role", null: false
    t.integer "sequence_number", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "financial_transaction_id"], name: "index_postings_on_account_transaction"
    t.index ["account_id"], name: "index_account_postings_on_account_id"
    t.index ["budget_workspace_id"], name: "index_account_postings_on_budget_workspace_id"
    t.index ["financial_transaction_id", "sequence_number"], name: "uidx_postings_transaction_sequence", unique: true
    t.index ["financial_transaction_id"], name: "index_account_postings_on_financial_transaction_id"
    t.index ["id", "budget_workspace_id"], name: "uidx_postings_id_workspace", unique: true
    t.check_constraint "amount <> 0::numeric", name: "postings_amount_nonzero"
    t.check_constraint "currency_code::text ~ '^[A-Z]{3}$'::text", name: "postings_currency_valid"
    t.check_constraint "role::text = ANY (ARRAY['primary'::character varying, 'source'::character varying, 'destination'::character varying, 'adjustment'::character varying]::text[])", name: "postings_role_valid"
    t.check_constraint "sequence_number >= 0", name: "postings_sequence_nonnegative"
  end

  create_table "account_snapshots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "available_balance", precision: 14, scale: 2
    t.decimal "balance", precision: 14, scale: 2, null: false
    t.datetime "created_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.text "notes"
    t.date "recorded_on", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "recorded_on"], name: "index_account_snapshots_on_account_id_and_recorded_on", unique: true
    t.index ["account_id"], name: "index_account_snapshots_on_account_id"
    t.index ["recorded_on"], name: "index_account_snapshots_on_recorded_on"
    t.check_constraint "lock_version >= 0", name: "account_snapshots_lock_version_nonnegative"
  end

  create_table "accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "archived_at"
    t.uuid "budget_workspace_id"
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.string "currency_code", limit: 3
    t.boolean "include_in_cash", default: false, null: false
    t.boolean "include_in_net_worth", default: true, null: false
    t.string "institution_name"
    t.integer "kind", default: 0, null: false
    t.integer "lock_version", default: 0, null: false
    t.string "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index "budget_workspace_id, lower((name)::text)", name: "uidx_active_accounts_workspace_name", unique: true, where: "((budget_workspace_id IS NOT NULL) AND (archived_at IS NULL))"
    t.index ["active"], name: "index_accounts_on_active"
    t.index ["budget_workspace_id"], name: "index_accounts_on_budget_workspace_id"
    t.index ["id", "budget_workspace_id", "currency_code"], name: "uidx_accounts_id_workspace_currency", unique: true
    t.index ["id", "budget_workspace_id"], name: "uidx_accounts_id_workspace", unique: true
    t.index ["id", "user_id"], name: "uidx_accounts_id_user", unique: true
    t.index ["kind"], name: "index_accounts_on_kind"
    t.index ["user_id", "active", "name"], name: "index_accounts_on_user_active_name", order: { active: :desc }
    t.index ["user_id", "name"], name: "index_accounts_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_accounts_on_user_id"
    t.check_constraint "kind >= 0 AND kind <= 8", name: "accounts_kind_valid"
    t.check_constraint "lock_version >= 0", name: "accounts_lock_version_nonnegative"
  end

  add_check_constraint "accounts", "currency_code IS NULL OR currency_code::text ~ '^[A-Z]{3}$'::text", name: "accounts_currency_valid", validate: false

  create_table "admin_audit_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.uuid "admin_user_id", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.jsonb "metadata", default: {}, null: false
    t.uuid "target_user_id"
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["action"], name: "index_admin_audit_logs_on_action"
    t.index ["admin_user_id"], name: "index_admin_audit_logs_on_admin_user_id"
    t.index ["created_at"], name: "index_admin_audit_logs_on_created_at"
    t.index ["target_user_id"], name: "index_admin_audit_logs_on_target_user_id"
  end

  create_table "admin_users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.datetime "locked_at"
    t.datetime "remember_created_at"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admin_users_on_email", unique: true
    t.index ["locked_at"], name: "index_admin_users_on_locked_at"
    t.index ["remember_created_at"], name: "index_admin_users_on_remember_created_at"
    t.index ["unlock_token"], name: "index_admin_users_on_unlock_token", unique: true
    t.check_constraint "failed_attempts >= 0", name: "admin_users_failed_attempts_nonnegative"
  end

  create_table "audit_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "action", null: false
    t.uuid "actor_admin_user_id"
    t.uuid "actor_membership_id"
    t.uuid "actor_user_id"
    t.uuid "budget_workspace_id", null: false
    t.jsonb "changed_fields", default: {}, null: false
    t.string "correlation_id"
    t.datetime "created_at", null: false
    t.uuid "entity_id", null: false
    t.string "entity_type", null: false
    t.datetime "event_at", null: false
    t.uuid "operation_run_id"
    t.string "request_id"
    t.string "source_ip"
    t.text "user_agent"
    t.index ["actor_admin_user_id"], name: "index_audit_events_on_actor_admin_user_id"
    t.index ["actor_membership_id"], name: "index_audit_events_on_actor_membership_id"
    t.index ["actor_user_id"], name: "index_audit_events_on_actor_user_id"
    t.index ["budget_workspace_id", "entity_type", "entity_id", "event_at"], name: "index_audit_events_on_entity_event"
    t.index ["budget_workspace_id", "event_at"], name: "index_audit_events_on_workspace_event", order: { event_at: :desc }
    t.index ["budget_workspace_id"], name: "index_audit_events_on_budget_workspace_id"
    t.index ["id", "budget_workspace_id"], name: "uidx_audit_events_id_workspace", unique: true
    t.index ["operation_run_id"], name: "index_audit_events_on_operation_run_id"
    t.check_constraint "action::text = ANY (ARRAY['create'::character varying, 'edit'::character varying, 'void'::character varying, 'reverse'::character varying, 'archive'::character varying, 'import'::character varying, 'import_reversal'::character varying, 'match'::character varying, 'unmatch'::character varying, 'generate'::character varying, 'trust_observation'::character varying, 'supersede_observation'::character varying, 'close'::character varying, 'reopen'::character varying, 'backup_export'::character varying, 'backup_restore'::character varying, 'access_change'::character varying, 'resolve_migration_discrepancy'::character varying, 'restore_checkpoint'::character varying, 'restore_rollback'::character varying]::text[])", name: "audit_events_action_valid"
  end

  create_table "backup_export_artifacts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "budget_workspace_id", null: false
    t.string "content_type", default: "application/json; charset=utf-8", null: false
    t.datetime "created_at", null: false
    t.uuid "data_transfer_run_id", null: false
    t.text "encrypted_contents"
    t.text "encrypted_export_password"
    t.datetime "expired_at"
    t.datetime "expires_at", null: false
    t.datetime "failed_at"
    t.string "filename"
    t.string "generation_key", null: false
    t.integer "lock_version", default: 0, null: false
    t.uuid "operation_run_id", null: false
    t.datetime "ready_at"
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["budget_workspace_id"], name: "index_backup_export_artifacts_on_budget_workspace_id"
    t.index ["data_transfer_run_id"], name: "index_backup_export_artifacts_on_data_transfer_run_id"
    t.index ["data_transfer_run_id"], name: "uidx_backup_export_artifacts_transfer", unique: true
    t.index ["expires_at"], name: "index_backup_export_artifacts_on_expiration", where: "((state)::text = ANY ((ARRAY['ready'::character varying, 'failed'::character varying])::text[]))"
    t.index ["id", "budget_workspace_id"], name: "uidx_backup_export_artifacts_id_workspace", unique: true
    t.index ["operation_run_id"], name: "index_backup_export_artifacts_on_operation_run_id"
    t.index ["operation_run_id"], name: "uidx_backup_export_artifacts_operation", unique: true
    t.index ["user_id", "state", "expires_at"], name: "index_backup_export_artifacts_on_owner_state"
    t.index ["user_id"], name: "index_backup_export_artifacts_on_user_id"
    t.check_constraint "(state::text = 'expired'::text) = (expired_at IS NOT NULL)", name: "backup_export_artifacts_expired_coherent"
    t.check_constraint "(state::text = 'failed'::text) = (failed_at IS NOT NULL)", name: "backup_export_artifacts_failed_coherent"
    t.check_constraint "(state::text = 'ready'::text) = (ready_at IS NOT NULL)", name: "backup_export_artifacts_ready_coherent"
    t.check_constraint "expires_at > created_at", name: "backup_export_artifacts_expiration_valid"
    t.check_constraint "lock_version >= 0", name: "backup_export_artifacts_lock_version_nonnegative"
    t.check_constraint "state::text <> 'ready'::text OR encrypted_contents IS NOT NULL AND filename IS NOT NULL", name: "backup_export_artifacts_contents_coherent"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying, 'ready'::character varying, 'failed'::character varying, 'expired'::character varying]::text[])", name: "backup_export_artifacts_state_valid"
  end

  create_table "backup_restore_drafts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "budget_workspace_id", null: false
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.uuid "data_transfer_run_id"
    t.text "encrypted_payload", null: false
    t.datetime "expired_at"
    t.datetime "expires_at", null: false
    t.datetime "failed_at"
    t.integer "lock_version", default: 0, null: false
    t.uuid "operation_run_id"
    t.string "payload_checksum", null: false
    t.string "payload_format_version", null: false
    t.boolean "replacement_requested", default: false, null: false
    t.uuid "restore_checkpoint_id"
    t.jsonb "selected_scopes", default: [], null: false
    t.boolean "source_encrypted", default: false, null: false
    t.string "state", default: "previewed", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.jsonb "validation_manifest", default: {}, null: false
    t.index ["budget_workspace_id"], name: "index_backup_restore_drafts_on_budget_workspace_id"
    t.index ["data_transfer_run_id"], name: "index_backup_restore_drafts_on_data_transfer_run_id"
    t.index ["data_transfer_run_id"], name: "uidx_backup_restore_drafts_transfer", unique: true, where: "(data_transfer_run_id IS NOT NULL)"
    t.index ["expires_at"], name: "index_backup_restore_drafts_on_expiration", where: "((state)::text = ANY ((ARRAY['previewed'::character varying, 'failed'::character varying])::text[]))"
    t.index ["id", "budget_workspace_id"], name: "uidx_backup_restore_drafts_id_workspace", unique: true
    t.index ["operation_run_id"], name: "index_backup_restore_drafts_on_operation_run_id"
    t.index ["operation_run_id"], name: "uidx_backup_restore_drafts_operation", unique: true, where: "(operation_run_id IS NOT NULL)"
    t.index ["restore_checkpoint_id"], name: "index_backup_restore_drafts_on_restore_checkpoint_id"
    t.index ["token_digest"], name: "uidx_backup_restore_drafts_token", unique: true
    t.index ["user_id", "state", "expires_at"], name: "index_backup_restore_drafts_on_owner_state"
    t.index ["user_id"], name: "index_backup_restore_drafts_on_user_id"
    t.check_constraint "(state::text = 'consumed'::text) = (consumed_at IS NOT NULL)", name: "backup_restore_drafts_consumed_coherent"
    t.check_constraint "(state::text = 'expired'::text) = (expired_at IS NOT NULL)", name: "backup_restore_drafts_expired_coherent"
    t.check_constraint "(state::text = 'failed'::text) = (failed_at IS NOT NULL)", name: "backup_restore_drafts_failed_coherent"
    t.check_constraint "expires_at > created_at", name: "backup_restore_drafts_expiration_valid"
    t.check_constraint "jsonb_typeof(selected_scopes) = 'array'::text", name: "backup_restore_drafts_scopes_array"
    t.check_constraint "jsonb_typeof(validation_manifest) = 'object'::text", name: "backup_restore_drafts_manifest_object"
    t.check_constraint "lock_version >= 0", name: "backup_restore_drafts_lock_version_nonnegative"
    t.check_constraint "payload_checksum::text ~ '^[0-9a-f]{64}$'::text", name: "backup_restore_drafts_checksum_valid"
    t.check_constraint "state::text = ANY (ARRAY['previewed'::character varying, 'queued'::character varying, 'consumed'::character varying, 'failed'::character varying, 'expired'::character varying]::text[])", name: "backup_restore_drafts_state_valid"
    t.check_constraint "token_digest::text ~ '^[0-9a-f]{64}$'::text", name: "backup_restore_drafts_token_valid"
  end

  create_table "balance_observations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.uuid "actor_membership_id"
    t.decimal "available_balance", precision: 19, scale: 4
    t.decimal "balance", precision: 19, scale: 4, null: false
    t.uuid "budget_workspace_id", null: false
    t.datetime "created_at", null: false
    t.string "currency_code", limit: 3, null: false
    t.datetime "effective_through_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.text "notes"
    t.datetime "observed_at", null: false
    t.uuid "source_import_batch_id"
    t.uuid "source_import_row_id"
    t.string "source_kind", null: false
    t.string "status", default: "trusted", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "effective_through_at", "created_at"], name: "index_observations_on_account_effective", order: { effective_through_at: :desc, created_at: :desc }
    t.index ["account_id"], name: "index_balance_observations_on_account_id"
    t.index ["actor_membership_id"], name: "index_balance_observations_on_actor_membership_id"
    t.index ["budget_workspace_id"], name: "index_balance_observations_on_budget_workspace_id"
    t.index ["id", "budget_workspace_id"], name: "uidx_observations_id_workspace", unique: true
    t.index ["source_import_batch_id"], name: "index_balance_observations_on_source_import_batch_id"
    t.index ["source_import_row_id"], name: "index_balance_observations_on_source_import_row_id"
    t.check_constraint "currency_code::text ~ '^[A-Z]{3}$'::text", name: "observations_currency_valid"
    t.check_constraint "lock_version >= 0", name: "observations_lock_version_nonnegative"
    t.check_constraint "observed_at >= effective_through_at", name: "observations_effective_window_valid"
    t.check_constraint "source_kind::text = ANY (ARRAY['manual'::character varying, 'institution_file'::character varying, 'migration'::character varying, 'adjustment'::character varying]::text[])", name: "observations_source_kind_valid"
    t.check_constraint "status::text = ANY (ARRAY['trusted'::character varying, 'superseded'::character varying, 'disputed'::character varying]::text[])", name: "observations_status_valid"
  end

  create_table "budget_allocations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "amount", precision: 19, scale: 4, null: false
    t.uuid "budget_item_id", null: false
    t.uuid "budget_workspace_id", null: false
    t.datetime "created_at", null: false
    t.string "currency_code", limit: 3, null: false
    t.uuid "financial_transaction_id", null: false
    t.integer "lock_version", default: 0, null: false
    t.decimal "match_confidence", precision: 5, scale: 4
    t.string "match_kind", null: false
    t.datetime "matched_at", null: false
    t.uuid "matched_by_membership_id"
    t.datetime "updated_at", null: false
    t.index ["budget_item_id", "financial_transaction_id"], name: "uidx_allocations_item_transaction", unique: true
    t.index ["budget_item_id"], name: "index_budget_allocations_on_budget_item_id"
    t.index ["budget_workspace_id"], name: "index_budget_allocations_on_budget_workspace_id"
    t.index ["financial_transaction_id"], name: "index_budget_allocations_on_financial_transaction_id"
    t.index ["id", "budget_workspace_id"], name: "uidx_allocations_id_workspace", unique: true
    t.index ["matched_by_membership_id"], name: "index_budget_allocations_on_matched_by_membership_id"
    t.check_constraint "amount > 0::numeric", name: "allocations_amount_positive"
    t.check_constraint "currency_code::text ~ '^[A-Z]{3}$'::text", name: "allocations_currency_valid"
    t.check_constraint "lock_version >= 0", name: "allocations_lock_version_nonnegative"
    t.check_constraint "match_confidence IS NULL OR match_confidence >= 0::numeric AND match_confidence <= 1::numeric", name: "allocations_confidence_valid"
    t.check_constraint "match_kind::text = ANY (ARRAY['manual'::character varying, 'suggested'::character varying, 'exact_import'::character varying, 'migration'::character varying]::text[])", name: "allocations_match_kind_valid"
  end

  create_table "budget_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "budget_group", null: false
    t.uuid "budget_period_id", null: false
    t.uuid "budget_workspace_id", null: false
    t.uuid "category_id"
    t.string "category_snapshot"
    t.datetime "created_at", null: false
    t.string "currency_code", limit: 3, null: false
    t.string "flow_kind", null: false
    t.uuid "intended_destination_account_id"
    t.uuid "intended_source_account_id"
    t.integer "lock_version", default: 0, null: false
    t.string "name_snapshot"
    t.text "notes"
    t.string "origin_kind", default: "manual", null: false
    t.string "payee_snapshot"
    t.decimal "planned_amount", precision: 19, scale: 4, default: "0.0", null: false
    t.string "priority_classification"
    t.uuid "recurring_occurrence_id"
    t.date "scheduled_on"
    t.string "state", default: "open", null: false
    t.datetime "updated_at", null: false
    t.string "void_reason"
    t.datetime "voided_at"
    t.index ["budget_period_id", "state", "scheduled_on"], name: "index_budget_items_on_period_state_schedule"
    t.index ["budget_period_id"], name: "index_budget_items_on_budget_period_id"
    t.index ["budget_workspace_id", "state", "scheduled_on"], name: "index_budget_items_on_workspace_state_schedule"
    t.index ["budget_workspace_id"], name: "index_budget_items_on_budget_workspace_id"
    t.index ["category_id"], name: "index_budget_items_on_category_id"
    t.index ["id", "budget_workspace_id", "currency_code"], name: "uidx_items_id_workspace_currency", unique: true
    t.index ["id", "budget_workspace_id"], name: "uidx_budget_items_id_workspace", unique: true
    t.index ["intended_destination_account_id"], name: "index_budget_items_on_intended_destination_account_id"
    t.index ["intended_source_account_id"], name: "index_budget_items_on_intended_source_account_id"
    t.index ["recurring_occurrence_id"], name: "index_budget_items_on_recurring_occurrence_id"
    t.check_constraint "(state::text = 'voided'::text) = (voided_at IS NOT NULL AND void_reason IS NOT NULL AND btrim(void_reason::text) <> ''::text)", name: "budget_items_void_state_coherent"
    t.check_constraint "budget_group::text = ANY (ARRAY['fixed'::character varying, 'variable'::character varying, 'debt'::character varying, 'savings'::character varying, 'other'::character varying]::text[])", name: "budget_items_budget_group_valid"
    t.check_constraint "currency_code::text ~ '^[A-Z]{3}$'::text", name: "budget_items_currency_valid"
    t.check_constraint "flow_kind::text = ANY (ARRAY['income'::character varying, 'outflow'::character varying, 'transfer'::character varying]::text[])", name: "budget_items_flow_kind_valid"
    t.check_constraint "intended_source_account_id IS NULL OR intended_destination_account_id IS NULL OR intended_source_account_id <> intended_destination_account_id", name: "budget_items_accounts_distinct"
    t.check_constraint "lock_version >= 0", name: "budget_items_lock_version_nonnegative"
    t.check_constraint "origin_kind::text = ANY (ARRAY['manual'::character varying, 'recurring'::character varying, 'clone'::character varying, 'budget_import'::character varying, 'migration'::character varying]::text[])", name: "budget_items_origin_valid"
    t.check_constraint "planned_amount >= 0::numeric", name: "budget_items_amount_nonnegative"
    t.check_constraint "priority_classification IS NULL OR (priority_classification::text = ANY (ARRAY['need'::character varying, 'want'::character varying, 'goal'::character varying, 'unclassified'::character varying]::text[]))", name: "budget_items_priority_valid"
    t.check_constraint "state::text = ANY (ARRAY['open'::character varying, 'skipped'::character varying, 'cancelled'::character varying, 'voided'::character varying]::text[])", name: "budget_items_state_valid"
  end

  create_table "budget_months", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "budget_workspace_id"
    t.datetime "created_at", null: false
    t.string "label", null: false
    t.decimal "leftover", precision: 12, scale: 2
    t.integer "lock_version", default: 0, null: false
    t.date "month_on", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["budget_workspace_id"], name: "index_budget_months_on_budget_workspace_id"
    t.index ["id", "user_id"], name: "uidx_budget_months_id_user", unique: true
    t.index ["user_id", "month_on"], name: "index_budget_months_on_user_id_and_month_on", unique: true
    t.index ["user_id"], name: "index_budget_months_on_user_id"
    t.check_constraint "EXTRACT(day FROM month_on) = 1::numeric", name: "budget_months_first_day"
    t.check_constraint "lock_version >= 0", name: "budget_months_lock_version_nonnegative"
  end

  create_table "budget_periods", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "budget_workspace_id", null: false
    t.datetime "created_at", null: false
    t.string "currency_code", limit: 3, null: false
    t.integer "lock_version", default: 0, null: false
    t.text "notes"
    t.date "starts_on", null: false
    t.string "state", default: "open", null: false
    t.datetime "updated_at", null: false
    t.index ["budget_workspace_id", "starts_on"], name: "uidx_periods_workspace_start", unique: true
    t.index ["budget_workspace_id"], name: "index_budget_periods_on_budget_workspace_id"
    t.index ["id", "budget_workspace_id", "currency_code"], name: "uidx_periods_id_workspace_currency", unique: true
    t.index ["id", "budget_workspace_id"], name: "uidx_periods_id_workspace", unique: true
    t.check_constraint "EXTRACT(day FROM starts_on) = 1::numeric", name: "periods_first_day"
    t.check_constraint "currency_code::text ~ '^[A-Z]{3}$'::text", name: "periods_currency_valid"
    t.check_constraint "lock_version >= 0", name: "periods_lock_version_nonnegative"
    t.check_constraint "state::text = ANY (ARRAY['open'::character varying, 'closing'::character varying, 'closed'::character varying, 'reopened'::character varying]::text[])", name: "periods_state_valid"
  end

  create_table "budget_workspaces", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.string "default_currency_code", limit: 3, default: "USD", null: false
    t.uuid "legacy_owner_user_id"
    t.integer "lock_version", default: 0, null: false
    t.string "name", null: false
    t.string "status", default: "active", null: false
    t.string "target_backfill_version"
    t.datetime "target_backfilled_at"
    t.boolean "target_reads_enabled", default: false, null: false
    t.boolean "target_writes_enabled", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["id", "default_currency_code"], name: "uidx_workspaces_id_currency", unique: true
    t.index ["legacy_owner_user_id"], name: "index_budget_workspaces_on_legacy_owner_user_id", unique: true
    t.check_constraint "(status::text = 'closed'::text) = (closed_at IS NOT NULL)", name: "workspaces_closed_state_coherent"
    t.check_constraint "NOT target_reads_enabled OR target_writes_enabled", name: "workspaces_target_read_requires_write"
    t.check_constraint "default_currency_code::text ~ '^[A-Z]{3}$'::text", name: "workspaces_currency_valid"
    t.check_constraint "lock_version >= 0", name: "workspaces_lock_version_nonnegative"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'suspended'::character varying, 'closing'::character varying, 'closed'::character varying]::text[])", name: "workspaces_status_valid"
  end

  create_table "categories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "archived_at"
    t.string "budget_group", null: false
    t.uuid "budget_workspace_id", null: false
    t.string "color_token"
    t.datetime "created_at", null: false
    t.integer "display_order", default: 0, null: false
    t.string "flow_kind", null: false
    t.integer "lock_version", default: 0, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "budget_workspace_id, lower((name)::text)", name: "uidx_active_categories_workspace_name", unique: true, where: "(archived_at IS NULL)"
    t.index ["budget_workspace_id", "flow_kind", "display_order"], name: "index_categories_on_workspace_flow_order"
    t.index ["budget_workspace_id"], name: "index_categories_on_budget_workspace_id"
    t.index ["id", "budget_workspace_id"], name: "uidx_categories_id_workspace", unique: true
    t.check_constraint "budget_group::text = ANY (ARRAY['fixed'::character varying, 'variable'::character varying, 'debt'::character varying, 'savings'::character varying, 'other'::character varying]::text[])", name: "categories_budget_group_valid"
    t.check_constraint "display_order >= 0", name: "categories_display_order_nonnegative"
    t.check_constraint "flow_kind::text = ANY (ARRAY['income'::character varying, 'outflow'::character varying, 'transfer'::character varying]::text[])", name: "categories_flow_kind_valid"
    t.check_constraint "lock_version >= 0", name: "categories_lock_version_nonnegative"
  end

  create_table "credit_card_payment_policies", primary_key: "planning_template_id", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid "budget_workspace_id", null: false
    t.datetime "created_at", null: false
    t.integer "due_day", null: false
    t.string "estimate_policy", default: "minimum", null: false
    t.uuid "liability_account_id", null: false
    t.integer "lock_version", default: 0, null: false
    t.decimal "minimum_payment", precision: 19, scale: 4, default: "0.0", null: false
    t.uuid "payment_account_id", null: false
    t.integer "priority", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["budget_workspace_id"], name: "index_credit_card_payment_policies_on_budget_workspace_id"
    t.index ["liability_account_id"], name: "index_credit_card_payment_policies_on_liability_account_id"
    t.index ["payment_account_id"], name: "index_credit_card_payment_policies_on_payment_account_id"
    t.index ["planning_template_id"], name: "index_credit_card_payment_policies_on_planning_template_id"
    t.check_constraint "due_day >= 1 AND due_day <= 31", name: "card_policies_due_day_valid"
    t.check_constraint "estimate_policy::text = ANY (ARRAY['minimum'::character varying, 'statement_balance'::character varying, 'available_cash'::character varying, 'fixed_amount'::character varying]::text[])", name: "card_policies_estimate_valid"
    t.check_constraint "liability_account_id <> payment_account_id", name: "card_policies_accounts_distinct"
    t.check_constraint "lock_version >= 0", name: "card_policies_lock_version_nonnegative"
    t.check_constraint "minimum_payment >= 0::numeric", name: "card_policies_minimum_nonnegative"
    t.check_constraint "priority > 0", name: "card_policies_priority_positive"
  end

  create_table "credit_cards", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account"
    t.boolean "active", default: true, null: false
    t.uuid "budget_workspace_id"
    t.datetime "created_at", null: false
    t.integer "due_day", default: 1, null: false
    t.uuid "linked_account_id"
    t.integer "lock_version", default: 0, null: false
    t.decimal "minimum_payment", precision: 12, scale: 2, default: "0.0", null: false
    t.string "name", null: false
    t.text "notes"
    t.uuid "payment_account_id"
    t.integer "priority", default: 1, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["active"], name: "index_credit_cards_on_active"
    t.index ["budget_workspace_id"], name: "index_credit_cards_on_budget_workspace_id"
    t.index ["due_day"], name: "index_credit_cards_on_due_day"
    t.index ["linked_account_id"], name: "index_credit_cards_on_linked_account_id"
    t.index ["payment_account_id"], name: "index_credit_cards_on_payment_account_id"
    t.index ["priority"], name: "index_credit_cards_on_priority"
    t.index ["user_id", "priority", "name"], name: "index_credit_cards_on_user_priority_name"
    t.index ["user_id"], name: "index_credit_cards_on_user_id"
    t.check_constraint "due_day >= 1 AND due_day <= 31", name: "credit_cards_due_day_valid"
    t.check_constraint "lock_version >= 0", name: "credit_cards_lock_version_nonnegative"
    t.check_constraint "minimum_payment >= 0::numeric", name: "credit_cards_minimum_nonnegative"
    t.check_constraint "priority >= 1", name: "credit_cards_priority_positive"
  end

  create_table "data_transfer_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_membership_id"
    t.uuid "budget_workspace_id", null: false
    t.string "checkpoint_reference"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "envelope_version"
    t.string "error_code"
    t.integer "lock_version", default: 0, null: false
    t.string "operation", null: false
    t.uuid "operation_run_id"
    t.string "payload_checksum", null: false
    t.string "payload_format_version", null: false
    t.jsonb "result_counts", default: {}, null: false
    t.jsonb "selected_scopes", default: [], null: false
    t.datetime "started_at"
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_membership_id"], name: "index_data_transfer_runs_on_actor_membership_id"
    t.index ["budget_workspace_id", "operation", "created_at"], name: "index_transfer_runs_on_workspace_operation"
    t.index ["budget_workspace_id"], name: "index_data_transfer_runs_on_budget_workspace_id"
    t.index ["id", "budget_workspace_id"], name: "uidx_transfer_runs_id_workspace", unique: true
    t.index ["operation_run_id"], name: "index_data_transfer_runs_on_operation_run_id"
    t.check_constraint "(state::text = ANY (ARRAY['succeeded'::character varying, 'failed'::character varying]::text[])) = (completed_at IS NOT NULL)", name: "transfer_runs_completion_state_coherent"
    t.check_constraint "lock_version >= 0", name: "transfer_runs_lock_version_nonnegative"
    t.check_constraint "operation::text = ANY (ARRAY['export'::character varying, 'preview'::character varying, 'restore'::character varying]::text[])", name: "transfer_runs_operation_valid"
    t.check_constraint "payload_checksum::text ~ '^[0-9a-f]{64}$'::text", name: "transfer_runs_checksum_valid"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'succeeded'::character varying, 'failed'::character varying]::text[])", name: "transfer_runs_state_valid"
  end

  create_table "expense_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account"
    t.decimal "actual_amount", precision: 12, scale: 2
    t.datetime "auto_completed_at"
    t.uuid "budget_month_id", null: false
    t.uuid "budget_workspace_id"
    t.string "category"
    t.datetime "created_at", null: false
    t.uuid "destination_account_id"
    t.string "generated_entry_key"
    t.integer "lock_version", default: 0, null: false
    t.string "need_or_want"
    t.text "notes"
    t.date "occurred_on"
    t.string "payee"
    t.decimal "planned_amount", precision: 12, scale: 2
    t.integer "section", default: 6, null: false
    t.uuid "source_account_id"
    t.string "source_file"
    t.uuid "source_template_id"
    t.string "source_template_type"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["auto_completed_at"], name: "index_expense_entries_on_auto_completed_at"
    t.index ["budget_month_id", "occurred_on", "created_at"], name: "index_expense_entries_on_month_chronological"
    t.index ["budget_month_id"], name: "index_expense_entries_on_budget_month_id"
    t.index ["budget_workspace_id"], name: "index_expense_entries_on_budget_workspace_id"
    t.index ["destination_account_id", "occurred_on", "created_at"], name: "index_expense_entries_on_destination_account_recent", order: { occurred_on: :desc, created_at: :desc }, where: "(destination_account_id IS NOT NULL)"
    t.index ["destination_account_id"], name: "index_expense_entries_on_destination_account_id"
    t.index ["generated_entry_key"], name: "index_expense_entries_on_generated_entry_key_unique", unique: true, where: "(generated_entry_key IS NOT NULL)"
    t.index ["id", "user_id"], name: "uidx_expense_entries_id_user", unique: true
    t.index ["occurred_on"], name: "index_expense_entries_on_occurred_on"
    t.index ["section"], name: "index_expense_entries_on_section"
    t.index ["source_account_id", "occurred_on", "created_at"], name: "index_expense_entries_on_source_account_recent", order: { occurred_on: :desc, created_at: :desc }, where: "(source_account_id IS NOT NULL)"
    t.index ["source_account_id"], name: "index_expense_entries_on_source_account_id"
    t.index ["source_template_type", "source_template_id"], name: "index_expense_entries_on_source_template"
    t.index ["status"], name: "index_expense_entries_on_status"
    t.index ["user_id", "status", "occurred_on"], name: "index_expense_entries_on_user_due_recurring", where: "((occurred_on IS NOT NULL) AND ((source_file)::text = ANY ((ARRAY['pay_schedule'::character varying, 'subscription'::character varying, 'monthly_bill'::character varying, 'payment_plan'::character varying])::text[])))"
    t.index ["user_id"], name: "index_expense_entries_on_user_id"
    t.check_constraint "actual_amount IS NULL OR actual_amount >= 0::numeric", name: "expense_entries_actual_amount_nonnegative"
    t.check_constraint "lock_version >= 0", name: "expense_entries_lock_version_nonnegative"
    t.check_constraint "planned_amount IS NULL OR planned_amount >= 0::numeric", name: "expense_entries_planned_amount_nonnegative"
    t.check_constraint "section >= 0 AND section <= 6", name: "expense_entries_section_valid"
    t.check_constraint "source_account_id IS NULL OR destination_account_id IS NULL OR source_account_id <> destination_account_id", name: "expense_entries_accounts_distinct"
    t.check_constraint "status >= 0 AND status <= 2", name: "expense_entries_status_valid"
  end

  create_table "financial_transactions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "budget_workspace_id", null: false
    t.uuid "category_id"
    t.datetime "created_at", null: false
    t.string "currency_code", limit: 3, null: false
    t.string "description", null: false
    t.date "effective_on", null: false
    t.string "flow_kind", null: false
    t.decimal "gross_amount", precision: 19, scale: 4, null: false
    t.string "idempotency_key"
    t.uuid "import_row_id"
    t.integer "lock_version", default: 0, null: false
    t.text "memo"
    t.string "origin_kind", null: false
    t.string "payee"
    t.date "posted_on"
    t.string "provider_transaction_id"
    t.uuid "reversal_transaction_id"
    t.string "state", default: "posted", null: false
    t.datetime "updated_at", null: false
    t.string "void_reason"
    t.datetime "voided_at"
    t.index ["budget_workspace_id", "effective_on"], name: "index_transactions_on_workspace_effective", order: { effective_on: :desc }
    t.index ["budget_workspace_id", "idempotency_key"], name: "uidx_transactions_workspace_idempotency", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["budget_workspace_id", "provider_transaction_id"], name: "uidx_transactions_workspace_provider_id", unique: true, where: "(provider_transaction_id IS NOT NULL)"
    t.index ["budget_workspace_id"], name: "index_financial_transactions_on_budget_workspace_id"
    t.index ["category_id"], name: "index_financial_transactions_on_category_id"
    t.index ["id", "budget_workspace_id", "currency_code"], name: "uidx_transactions_id_workspace_currency", unique: true
    t.index ["id", "budget_workspace_id"], name: "uidx_transactions_id_workspace", unique: true
    t.index ["import_row_id"], name: "index_financial_transactions_on_import_row_id", unique: true, where: "(import_row_id IS NOT NULL)"
    t.index ["reversal_transaction_id"], name: "index_financial_transactions_on_reversal_transaction_id"
    t.check_constraint "(state::text = 'voided'::text) = (voided_at IS NOT NULL AND void_reason IS NOT NULL AND btrim(void_reason::text) <> ''::text)", name: "transactions_void_state_coherent"
    t.check_constraint "currency_code::text ~ '^[A-Z]{3}$'::text", name: "transactions_currency_valid"
    t.check_constraint "flow_kind::text = ANY (ARRAY['income'::character varying, 'outflow'::character varying, 'transfer'::character varying, 'adjustment'::character varying]::text[])", name: "transactions_flow_kind_valid"
    t.check_constraint "gross_amount >= 0::numeric", name: "transactions_gross_nonnegative"
    t.check_constraint "lock_version >= 0", name: "transactions_lock_version_nonnegative"
    t.check_constraint "origin_kind::text = ANY (ARRAY['manual'::character varying, 'institution_import'::character varying, 'migration'::character varying, 'system_adjustment'::character varying]::text[])", name: "transactions_origin_valid"
    t.check_constraint "reversal_transaction_id IS NULL OR (state::text = ANY (ARRAY['reversed'::character varying, 'posted'::character varying]::text[]))", name: "transactions_reversal_coherent"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying, 'posted'::character varying, 'voided'::character varying, 'reversed'::character varying]::text[])", name: "transactions_state_valid"
  end

  create_table "import_batches", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.uuid "actor_membership_id"
    t.uuid "budget_workspace_id", null: false
    t.datetime "committed_at"
    t.date "coverage_ends_on"
    t.date "coverage_starts_on"
    t.datetime "created_at", null: false
    t.integer "duplicate_count", default: 0, null: false
    t.integer "error_count", default: 0, null: false
    t.datetime "failed_at"
    t.string "failure_code"
    t.string "file_digest", null: false
    t.string "fingerprint_version", null: false
    t.string "idempotency_key", null: false
    t.string "import_kind", null: false
    t.uuid "import_profile_id"
    t.integer "imported_count", default: 0, null: false
    t.integer "lock_version", default: 0, null: false
    t.string "mapping_version", null: false
    t.uuid "operation_run_id"
    t.string "original_filename", null: false
    t.string "parser_version", null: false
    t.jsonb "redacted_metadata", default: {}, null: false
    t.datetime "reverted_at"
    t.integer "row_count", default: 0, null: false
    t.string "status", default: "previewed", null: false
    t.datetime "updated_at", null: false
    t.jsonb "warnings", default: [], null: false
    t.index ["account_id"], name: "index_import_batches_on_account_id"
    t.index ["actor_membership_id"], name: "index_import_batches_on_actor_membership_id"
    t.index ["budget_workspace_id", "import_kind", "idempotency_key"], name: "uidx_import_batches_workspace_kind_key", unique: true
    t.index ["budget_workspace_id", "status", "created_at"], name: "index_import_batches_on_workspace_status_created"
    t.index ["budget_workspace_id"], name: "index_import_batches_on_budget_workspace_id"
    t.index ["id", "budget_workspace_id"], name: "uidx_import_batches_id_workspace", unique: true
    t.index ["import_profile_id"], name: "index_import_batches_on_import_profile_id"
    t.index ["operation_run_id"], name: "index_import_batches_on_operation_run_id"
    t.check_constraint "(imported_count + duplicate_count + error_count) <= row_count", name: "import_batches_counts_coherent"
    t.check_constraint "(status::text = ANY (ARRAY['committed'::character varying, 'reverting'::character varying, 'reverted'::character varying]::text[])) = (committed_at IS NOT NULL) AND (status::text = 'failed'::text) = (failed_at IS NOT NULL) AND (status::text = 'reverted'::text) = (reverted_at IS NOT NULL)", name: "import_batches_terminal_state_coherent"
    t.check_constraint "coverage_starts_on IS NULL OR coverage_ends_on IS NULL OR coverage_ends_on >= coverage_starts_on", name: "import_batches_coverage_valid"
    t.check_constraint "file_digest::text ~ '^[0-9a-f]{64}$'::text", name: "import_batches_digest_valid"
    t.check_constraint "import_kind::text = ANY (ARRAY['account_activity'::character varying, 'budget_plan'::character varying, 'backup_restore'::character varying]::text[])", name: "import_batches_kind_valid"
    t.check_constraint "lock_version >= 0", name: "import_batches_lock_version_nonnegative"
    t.check_constraint "row_count >= 0 AND imported_count >= 0 AND duplicate_count >= 0 AND error_count >= 0", name: "import_batches_counts_nonnegative"
    t.check_constraint "status::text = ANY (ARRAY['previewed'::character varying, 'committing'::character varying, 'committed'::character varying, 'failed'::character varying, 'reverting'::character varying, 'reverted'::character varying]::text[])", name: "import_batches_status_valid"
  end

  create_table "import_profiles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id"
    t.boolean "active", default: true, null: false
    t.string "amount_strategy", null: false
    t.uuid "budget_workspace_id", null: false
    t.jsonb "column_mapping", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "fingerprint_version", null: false
    t.integer "header_row_number", default: 1, null: false
    t.integer "lock_version", default: 0, null: false
    t.string "name", null: false
    t.string "parser_name", null: false
    t.string "parser_version", null: false
    t.datetime "updated_at", null: false
    t.index "budget_workspace_id, lower((name)::text)", name: "uidx_import_profiles_workspace_name", unique: true
    t.index ["account_id"], name: "index_import_profiles_on_account_id"
    t.index ["budget_workspace_id"], name: "index_import_profiles_on_budget_workspace_id"
    t.index ["id", "budget_workspace_id"], name: "uidx_import_profiles_id_workspace", unique: true
    t.check_constraint "amount_strategy::text = ANY (ARRAY['charges_are_negative'::character varying, 'charges_are_positive'::character varying, 'type_column'::character varying]::text[])", name: "import_profiles_amount_strategy_valid"
    t.check_constraint "header_row_number > 0", name: "import_profiles_header_positive"
    t.check_constraint "lock_version >= 0", name: "import_profiles_lock_version_nonnegative"
  end

  create_table "import_rows", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "budget_workspace_id", null: false
    t.datetime "created_at", null: false
    t.string "error_code"
    t.text "error_message"
    t.uuid "financial_transaction_id"
    t.string "fingerprint", null: false
    t.string "fingerprint_version", null: false
    t.uuid "import_batch_id", null: false
    t.string "normalization_result", null: false
    t.jsonb "normalized_payload", default: {}, null: false
    t.string "provider_transaction_id"
    t.jsonb "raw_payload", default: {}, null: false
    t.integer "row_number", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["budget_workspace_id", "fingerprint_version", "fingerprint"], name: "index_import_rows_on_workspace_fingerprint"
    t.index ["budget_workspace_id"], name: "index_import_rows_on_budget_workspace_id"
    t.index ["financial_transaction_id"], name: "index_import_rows_on_financial_transaction_id"
    t.index ["id", "budget_workspace_id"], name: "uidx_import_rows_id_workspace", unique: true
    t.index ["import_batch_id", "row_number"], name: "uidx_import_rows_batch_row", unique: true
    t.index ["import_batch_id"], name: "index_import_rows_on_import_batch_id"
    t.check_constraint "normalization_result::text = ANY (ARRAY['normalized'::character varying, 'duplicate'::character varying, 'invalid'::character varying, 'unsupported'::character varying]::text[])", name: "import_rows_normalization_valid"
    t.check_constraint "row_number > 0", name: "import_rows_number_positive"
    t.check_constraint "status::text <> 'rejected'::text OR error_code IS NOT NULL", name: "import_rows_rejection_coherent"
    t.check_constraint "status::text = ANY (ARRAY['accepted'::character varying, 'duplicate'::character varying, 'rejected'::character varying, 'reversed'::character varying]::text[])", name: "import_rows_status_valid"
  end

  create_table "legacy_record_mappings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "budget_workspace_id", null: false
    t.datetime "created_at", null: false
    t.uuid "legacy_record_id", null: false
    t.string "legacy_record_type", null: false
    t.string "mapping_version", null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "source_checksum"
    t.string "status", default: "mapped", null: false
    t.uuid "target_record_id", null: false
    t.string "target_record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["budget_workspace_id", "legacy_record_type", "legacy_record_id", "target_record_type"], name: "uidx_legacy_mappings_source_target_type", unique: true
    t.index ["budget_workspace_id", "target_record_type", "target_record_id"], name: "index_legacy_mappings_target"
    t.index ["budget_workspace_id"], name: "index_legacy_record_mappings_on_budget_workspace_id"
    t.check_constraint "source_checksum IS NULL OR source_checksum::text ~ '^[0-9a-f]{64}$'::text", name: "legacy_mappings_checksum_valid"
    t.check_constraint "status::text = ANY (ARRAY['mapped'::character varying, 'omitted'::character varying, 'quarantined'::character varying]::text[])", name: "legacy_mappings_status_valid"
  end

  create_table "migration_discrepancies", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "budget_workspace_id", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.uuid "legacy_record_id", null: false
    t.string "legacy_record_type", null: false
    t.uuid "operation_run_id"
    t.jsonb "redacted_details", default: {}, null: false
    t.datetime "resolved_at"
    t.string "status", default: "open", null: false
    t.datetime "updated_at", null: false
    t.index ["budget_workspace_id", "legacy_record_type", "legacy_record_id", "code"], name: "uidx_migration_discrepancies_source_code", unique: true
    t.index ["budget_workspace_id", "status", "created_at"], name: "index_migration_discrepancies_on_workspace_status"
    t.index ["budget_workspace_id"], name: "index_migration_discrepancies_on_budget_workspace_id"
    t.index ["operation_run_id"], name: "index_migration_discrepancies_on_operation_run_id"
    t.check_constraint "status::text = 'open'::text OR resolved_at IS NOT NULL", name: "migration_discrepancies_resolution_coherent"
    t.check_constraint "status::text = ANY (ARRAY['open'::character varying, 'resolved'::character varying, 'accepted'::character varying]::text[])", name: "migration_discrepancies_status_valid"
  end

  create_table "month_close_item_snapshots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "actual_amount", precision: 19, scale: 4, default: "0.0", null: false
    t.string "budget_group", null: false
    t.uuid "budget_item_id", null: false
    t.uuid "budget_workspace_id", null: false
    t.string "category_snapshot"
    t.datetime "created_at", null: false
    t.string "currency_code", limit: 3, null: false
    t.string "flow_kind", null: false
    t.uuid "month_close_id", null: false
    t.string "name_snapshot"
    t.decimal "planned_amount", precision: 19, scale: 4, null: false
    t.decimal "remaining_amount", precision: 19, scale: 4, default: "0.0", null: false
    t.date "scheduled_on"
    t.datetime "updated_at", null: false
    t.index ["budget_item_id"], name: "index_month_close_item_snapshots_on_budget_item_id"
    t.index ["budget_workspace_id"], name: "index_month_close_item_snapshots_on_budget_workspace_id"
    t.index ["month_close_id", "budget_item_id"], name: "uidx_close_item_snapshots_close_item", unique: true
    t.index ["month_close_id", "flow_kind"], name: "idx_close_item_snapshots_close_flow"
    t.index ["month_close_id"], name: "index_month_close_item_snapshots_on_month_close_id"
    t.check_constraint "currency_code::text ~ '^[A-Z]{3}$'::text", name: "close_item_snapshots_currency_valid"
    t.check_constraint "flow_kind::text = ANY (ARRAY['income'::character varying, 'outflow'::character varying, 'transfer'::character varying]::text[])", name: "close_item_snapshots_flow_valid"
    t.check_constraint "planned_amount >= 0::numeric AND actual_amount >= 0::numeric AND remaining_amount >= 0::numeric", name: "close_item_snapshots_amounts_nonnegative"
  end

  create_table "month_close_transaction_snapshots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "allocated_amount", precision: 19, scale: 4, default: "0.0", null: false
    t.uuid "budget_workspace_id", null: false
    t.string "category_snapshot"
    t.datetime "created_at", null: false
    t.string "currency_code", limit: 3, null: false
    t.string "description_snapshot", null: false
    t.date "effective_on", null: false
    t.uuid "financial_transaction_id", null: false
    t.string "flow_kind", null: false
    t.decimal "gross_amount", precision: 19, scale: 4, null: false
    t.uuid "month_close_id", null: false
    t.string "origin_kind", null: false
    t.datetime "updated_at", null: false
    t.index ["budget_workspace_id"], name: "index_month_close_transaction_snapshots_on_budget_workspace_id"
    t.index ["financial_transaction_id"], name: "idx_on_financial_transaction_id_0253eecd13"
    t.index ["month_close_id", "financial_transaction_id"], name: "uidx_close_transaction_snapshots_close_transaction", unique: true
    t.index ["month_close_id", "flow_kind", "category_snapshot"], name: "idx_close_transaction_snapshots_reporting"
    t.index ["month_close_id"], name: "index_month_close_transaction_snapshots_on_month_close_id"
    t.check_constraint "currency_code::text ~ '^[A-Z]{3}$'::text", name: "close_transaction_snapshots_currency_valid"
    t.check_constraint "flow_kind::text = ANY (ARRAY['income'::character varying, 'outflow'::character varying, 'transfer'::character varying, 'adjustment'::character varying]::text[])", name: "close_transaction_snapshots_flow_valid"
    t.check_constraint "gross_amount >= 0::numeric AND allocated_amount >= 0::numeric AND allocated_amount <= gross_amount", name: "close_transaction_snapshots_amounts_valid"
  end

  create_table "month_closes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "actual_income", precision: 19, scale: 4, default: "0.0", null: false
    t.decimal "actual_net", precision: 19, scale: 4, default: "0.0", null: false
    t.decimal "actual_outflow", precision: 19, scale: 4, default: "0.0", null: false
    t.uuid "budget_period_id", null: false
    t.uuid "budget_workspace_id", null: false
    t.string "calculation_input_digest", null: false
    t.string "calculation_version", null: false
    t.uuid "close_operation_id"
    t.datetime "closed_at", null: false
    t.uuid "closed_by_membership_id"
    t.datetime "created_at", null: false
    t.decimal "forecast_income", precision: 19, scale: 4, default: "0.0", null: false
    t.decimal "forecast_net", precision: 19, scale: 4, default: "0.0", null: false
    t.decimal "forecast_outflow", precision: 19, scale: 4, default: "0.0", null: false
    t.decimal "income_variance", precision: 19, scale: 4, default: "0.0", null: false
    t.decimal "outflow_variance", precision: 19, scale: 4, default: "0.0", null: false
    t.decimal "planned_income", precision: 19, scale: 4, default: "0.0", null: false
    t.decimal "planned_net", precision: 19, scale: 4, default: "0.0", null: false
    t.decimal "planned_outflow", precision: 19, scale: 4, default: "0.0", null: false
    t.decimal "remaining_income", precision: 19, scale: 4, default: "0.0", null: false
    t.decimal "remaining_outflow", precision: 19, scale: 4, default: "0.0", null: false
    t.uuid "reopens_month_close_id"
    t.string "state", default: "closed", null: false
    t.integer "unmatched_count", default: 0, null: false
    t.integer "unresolved_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["budget_period_id"], name: "index_month_closes_on_budget_period_id"
    t.index ["budget_period_id"], name: "uidx_active_month_close", unique: true, where: "((state)::text = 'closed'::text)"
    t.index ["budget_workspace_id"], name: "index_month_closes_on_budget_workspace_id"
    t.index ["close_operation_id"], name: "index_month_closes_on_close_operation_id"
    t.index ["closed_by_membership_id"], name: "index_month_closes_on_closed_by_membership_id"
    t.index ["id", "budget_workspace_id"], name: "uidx_month_closes_id_workspace", unique: true
    t.index ["reopens_month_close_id"], name: "index_month_closes_on_reopens_month_close_id"
    t.check_constraint "calculation_input_digest::text ~ '^[0-9a-f]{64}$'::text", name: "month_closes_digest_valid"
    t.check_constraint "state::text = ANY (ARRAY['closed'::character varying, 'superseded'::character varying]::text[])", name: "month_closes_state_valid"
    t.check_constraint "unresolved_count >= 0 AND unmatched_count >= 0", name: "month_closes_counts_nonnegative"
  end

  create_table "monthly_bills", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account"
    t.boolean "active", default: true, null: false
    t.integer "billing_frequency", default: 0, null: false
    t.integer "billing_months", default: [], null: false, array: true
    t.uuid "budget_workspace_id"
    t.datetime "created_at", null: false
    t.decimal "default_amount", precision: 12, scale: 2
    t.integer "due_day", default: 1, null: false
    t.integer "kind", default: 0, null: false
    t.uuid "linked_account_id"
    t.integer "lock_version", default: 0, null: false
    t.string "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["active"], name: "index_monthly_bills_on_active"
    t.index ["budget_workspace_id"], name: "index_monthly_bills_on_budget_workspace_id"
    t.index ["kind"], name: "index_monthly_bills_on_kind"
    t.index ["linked_account_id"], name: "index_monthly_bills_on_linked_account_id"
    t.index ["user_id", "kind", "due_day", "name"], name: "index_monthly_bills_on_user_kind_due_day_name"
    t.index ["user_id"], name: "index_monthly_bills_on_user_id"
    t.check_constraint "billing_frequency >= 0 AND billing_frequency <= 3", name: "monthly_bills_frequency_valid"
    t.check_constraint "billing_months <@ ARRAY[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]", name: "monthly_bills_months_valid"
    t.check_constraint "cardinality(billing_months) =\nCASE billing_frequency\n    WHEN 0 THEN 12\n    WHEN 1 THEN 4\n    WHEN 2 THEN 2\n    WHEN 3 THEN 1\n    ELSE NULL::integer\nEND", name: "monthly_bills_month_count_valid"
    t.check_constraint "default_amount IS NULL OR default_amount >= 0::numeric", name: "monthly_bills_amount_nonnegative"
    t.check_constraint "due_day >= 1 AND due_day <= 31", name: "monthly_bills_due_day_valid"
    t.check_constraint "kind >= 0 AND kind <= 1", name: "monthly_bills_kind_valid"
    t.check_constraint "lock_version >= 0", name: "monthly_bills_lock_version_nonnegative"
  end

  create_table "operation_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_membership_id"
    t.uuid "budget_workspace_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "enqueued_at"
    t.string "error_code"
    t.string "idempotency_key", null: false
    t.jsonb "job_arguments", default: [], null: false
    t.string "job_class"
    t.datetime "last_enqueue_attempt_at"
    t.datetime "last_heartbeat_at"
    t.integer "lock_version", default: 0, null: false
    t.string "operation_type", null: false
    t.integer "progress_current", default: 0, null: false
    t.string "progress_label"
    t.integer "progress_total"
    t.jsonb "redacted_parameters", default: {}, null: false
    t.string "request_digest", null: false
    t.jsonb "result_counts", default: {}, null: false
    t.jsonb "result_reference", default: {}, null: false
    t.boolean "retryable", default: false, null: false
    t.datetime "started_at"
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_membership_id"], name: "index_operation_runs_on_actor_membership_id"
    t.index ["budget_workspace_id", "operation_type", "idempotency_key"], name: "uidx_operations_workspace_type_key", unique: true
    t.index ["budget_workspace_id", "state", "created_at"], name: "index_operations_on_workspace_state_created"
    t.index ["budget_workspace_id"], name: "index_operation_runs_on_budget_workspace_id"
    t.index ["id", "budget_workspace_id"], name: "uidx_operations_id_workspace", unique: true
    t.index ["state", "enqueued_at", "last_enqueue_attempt_at"], name: "index_operations_on_pending_dispatch", where: "((job_class IS NOT NULL) AND ((state)::text = 'pending'::text))"
    t.check_constraint "(state::text = ANY (ARRAY['succeeded'::character varying, 'failed'::character varying, 'reversed'::character varying]::text[])) = (completed_at IS NOT NULL)", name: "operations_completion_state_coherent"
    t.check_constraint "enqueued_at IS NULL OR job_class IS NOT NULL", name: "operations_enqueue_state_coherent"
    t.check_constraint "job_class IS NOT NULL OR job_arguments = '[]'::jsonb", name: "operations_job_metadata_coherent"
    t.check_constraint "jsonb_typeof(job_arguments) = 'array'::text", name: "operations_job_arguments_array"
    t.check_constraint "lock_version >= 0", name: "operations_lock_version_nonnegative"
    t.check_constraint "progress_current >= 0 AND (progress_total IS NULL OR progress_total >= 0 AND progress_current <= progress_total)", name: "operations_progress_valid"
    t.check_constraint "request_digest::text ~ '^[0-9a-f]{64}$'::text", name: "operations_request_digest_valid"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying, 'running'::character varying, 'succeeded'::character varying, 'failed'::character varying, 'reversed'::character varying]::text[])", name: "operations_state_valid"
  end

  create_table "pay_schedules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account"
    t.boolean "active", default: true, null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.uuid "budget_workspace_id"
    t.integer "cadence", default: 2, null: false
    t.datetime "created_at", null: false
    t.integer "day_of_month_one"
    t.integer "day_of_month_two"
    t.date "ends_on"
    t.date "first_pay_on", null: false
    t.uuid "linked_account_id"
    t.integer "lock_version", default: 0, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.integer "weekend_adjustment", default: 1, null: false
    t.index ["active"], name: "index_pay_schedules_on_active"
    t.index ["budget_workspace_id"], name: "index_pay_schedules_on_budget_workspace_id"
    t.index ["cadence"], name: "index_pay_schedules_on_cadence"
    t.index ["linked_account_id"], name: "index_pay_schedules_on_linked_account_id"
    t.index ["user_id", "active", "first_pay_on", "ends_on"], name: "index_pay_schedules_on_user_active_date_window"
    t.index ["user_id", "name"], name: "index_pay_schedules_on_user_name"
    t.index ["user_id"], name: "index_pay_schedules_on_user_id"
    t.check_constraint "amount > 0::numeric", name: "pay_schedules_amount_positive"
    t.check_constraint "cadence >= 0 AND cadence <= 3", name: "pay_schedules_cadence_valid"
    t.check_constraint "day_of_month_one IS NULL OR day_of_month_one >= 1 AND day_of_month_one <= 31", name: "pay_schedules_first_day_valid"
    t.check_constraint "day_of_month_two IS NULL OR day_of_month_two >= 1 AND day_of_month_two <= 31", name: "pay_schedules_second_day_valid"
    t.check_constraint "ends_on IS NULL OR ends_on >= first_pay_on", name: "pay_schedules_date_window_valid"
    t.check_constraint "lock_version >= 0", name: "pay_schedules_lock_version_nonnegative"
    t.check_constraint "weekend_adjustment >= 0 AND weekend_adjustment <= 2", name: "pay_schedules_weekend_adjustment_valid"
  end

  create_table "payment_plan_terms", primary_key: "planning_template_id", id: :uuid, default: nil, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "monthly_target", precision: 19, scale: 4, default: "0.0", null: false
    t.decimal "opening_paid_adjustment", precision: 19, scale: 4, default: "0.0", null: false
    t.date "target_completion_on"
    t.decimal "total_due", precision: 19, scale: 4, null: false
    t.datetime "updated_at", null: false
    t.index ["planning_template_id"], name: "index_payment_plan_terms_on_planning_template_id"
    t.check_constraint "monthly_target >= 0::numeric", name: "payment_plan_terms_target_nonnegative"
    t.check_constraint "opening_paid_adjustment >= 0::numeric AND opening_paid_adjustment <= total_due", name: "payment_plan_terms_opening_valid"
    t.check_constraint "total_due > 0::numeric", name: "payment_plan_terms_total_positive"
  end

  create_table "payment_plans", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account"
    t.boolean "active", default: true, null: false
    t.decimal "amount_paid", precision: 12, scale: 2, default: "0.0", null: false
    t.uuid "budget_workspace_id"
    t.datetime "created_at", null: false
    t.integer "due_day", default: 15, null: false
    t.uuid "linked_account_id"
    t.integer "lock_version", default: 0, null: false
    t.decimal "monthly_target", precision: 12, scale: 2
    t.string "name", null: false
    t.text "notes"
    t.decimal "total_due", precision: 12, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["active"], name: "index_payment_plans_on_active"
    t.index ["budget_workspace_id"], name: "index_payment_plans_on_budget_workspace_id"
    t.index ["linked_account_id"], name: "index_payment_plans_on_linked_account_id"
    t.index ["user_id", "due_day", "name"], name: "index_payment_plans_on_user_due_day_name"
    t.index ["user_id"], name: "index_payment_plans_on_user_id"
    t.check_constraint "amount_paid <= total_due", name: "payment_plans_paid_within_total"
    t.check_constraint "amount_paid >= 0::numeric", name: "payment_plans_paid_nonnegative"
    t.check_constraint "due_day >= 1 AND due_day <= 31", name: "payment_plans_due_day_valid"
    t.check_constraint "lock_version >= 0", name: "payment_plans_lock_version_nonnegative"
    t.check_constraint "monthly_target IS NULL OR monthly_target >= 0::numeric", name: "payment_plans_target_nonnegative"
    t.check_constraint "total_due > 0::numeric", name: "payment_plans_total_positive"
  end

  create_table "planning_templates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "active_from"
    t.date "active_until"
    t.datetime "archived_at"
    t.string "budget_group", null: false
    t.uuid "budget_workspace_id", null: false
    t.uuid "category_id"
    t.datetime "created_at", null: false
    t.string "currency_code", limit: 3, null: false
    t.decimal "default_amount", precision: 19, scale: 4, default: "0.0", null: false
    t.uuid "destination_account_id"
    t.string "flow_kind", null: false
    t.string "kind", null: false
    t.integer "lock_version", default: 0, null: false
    t.string "name", null: false
    t.text "notes"
    t.uuid "source_account_id"
    t.datetime "updated_at", null: false
    t.index ["budget_workspace_id", "kind", "archived_at"], name: "index_templates_on_workspace_kind_archive"
    t.index ["budget_workspace_id", "kind", "name"], name: "index_templates_on_workspace_kind_name"
    t.index ["budget_workspace_id"], name: "index_planning_templates_on_budget_workspace_id"
    t.index ["category_id"], name: "index_planning_templates_on_category_id"
    t.index ["destination_account_id"], name: "index_planning_templates_on_destination_account_id"
    t.index ["id", "budget_workspace_id"], name: "uidx_templates_id_workspace", unique: true
    t.index ["source_account_id"], name: "index_planning_templates_on_source_account_id"
    t.check_constraint "active_from IS NULL OR active_until IS NULL OR active_until >= active_from", name: "templates_active_window_valid"
    t.check_constraint "budget_group::text = ANY (ARRAY['fixed'::character varying, 'variable'::character varying, 'debt'::character varying, 'savings'::character varying, 'other'::character varying]::text[])", name: "templates_budget_group_valid"
    t.check_constraint "currency_code::text ~ '^[A-Z]{3}$'::text", name: "templates_currency_valid"
    t.check_constraint "default_amount >= 0::numeric", name: "templates_amount_nonnegative"
    t.check_constraint "flow_kind::text = ANY (ARRAY['income'::character varying, 'outflow'::character varying, 'transfer'::character varying]::text[])", name: "templates_flow_kind_valid"
    t.check_constraint "kind::text = ANY (ARRAY['paycheck'::character varying, 'subscription'::character varying, 'bill'::character varying, 'payment_plan'::character varying, 'credit_card_payment'::character varying]::text[])", name: "templates_kind_valid"
    t.check_constraint "lock_version >= 0", name: "templates_lock_version_nonnegative"
    t.check_constraint "source_account_id IS NULL OR destination_account_id IS NULL OR source_account_id <> destination_account_id", name: "templates_accounts_distinct"
  end

  create_table "recurrence_months", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "month_number", null: false
    t.uuid "recurrence_rule_id", null: false
    t.datetime "updated_at", null: false
    t.index ["recurrence_rule_id", "month_number"], name: "uidx_recurrence_months_rule_month", unique: true
    t.index ["recurrence_rule_id"], name: "index_recurrence_months_on_recurrence_rule_id"
    t.check_constraint "month_number >= 1 AND month_number <= 12", name: "recurrence_months_number_valid"
  end

  create_table "recurrence_rules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "anchor_on", null: false
    t.string "cadence", null: false
    t.datetime "created_at", null: false
    t.integer "day_one"
    t.integer "day_two"
    t.date "ends_on"
    t.integer "interval_count", default: 1, null: false
    t.integer "lock_version", default: 0, null: false
    t.uuid "planning_template_id", null: false
    t.date "starts_on", null: false
    t.datetime "updated_at", null: false
    t.string "weekend_policy", default: "none", null: false
    t.index ["planning_template_id"], name: "index_recurrence_rules_on_planning_template_id", unique: true
    t.check_constraint "cadence::text = ANY (ARRAY['weekly'::character varying, 'monthly'::character varying, 'yearly'::character varying, 'custom_months'::character varying]::text[])", name: "recurrence_rules_cadence_valid"
    t.check_constraint "day_one IS NULL OR day_one >= 1 AND day_one <= 31", name: "recurrence_rules_day_one_valid"
    t.check_constraint "day_two IS NULL OR day_two >= 1 AND day_two <= 31", name: "recurrence_rules_day_two_valid"
    t.check_constraint "ends_on IS NULL OR ends_on >= starts_on", name: "recurrence_rules_window_valid"
    t.check_constraint "interval_count > 0", name: "recurrence_rules_interval_positive"
    t.check_constraint "lock_version >= 0", name: "recurrence_rules_lock_version_nonnegative"
    t.check_constraint "weekend_policy::text = ANY (ARRAY['none'::character varying, 'previous_friday'::character varying, 'next_monday'::character varying]::text[])", name: "recurrence_rules_weekend_valid"
  end

  create_table "recurring_occurrences", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "budget_item_id"
    t.uuid "budget_period_id", null: false
    t.uuid "budget_workspace_id", null: false
    t.datetime "created_at", null: false
    t.uuid "generation_operation_id"
    t.uuid "planning_template_id", null: false
    t.date "scheduled_on", null: false
    t.string "slot_key", default: "default", null: false
    t.string "state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["budget_item_id"], name: "index_recurring_occurrences_on_budget_item_id", unique: true
    t.index ["budget_period_id"], name: "index_recurring_occurrences_on_budget_period_id"
    t.index ["budget_workspace_id"], name: "index_recurring_occurrences_on_budget_workspace_id"
    t.index ["generation_operation_id"], name: "index_recurring_occurrences_on_generation_operation_id"
    t.index ["id", "budget_workspace_id"], name: "uidx_occurrences_id_workspace", unique: true
    t.index ["planning_template_id", "budget_period_id", "scheduled_on", "slot_key"], name: "uidx_occurrences_template_period_date_slot", unique: true
    t.index ["planning_template_id"], name: "index_recurring_occurrences_on_planning_template_id"
    t.check_constraint "state::text = ANY (ARRAY['pending'::character varying, 'materialized'::character varying, 'skipped'::character varying, 'cancelled'::character varying, 'failed'::character varying]::text[])", name: "occurrences_state_valid"
  end

  create_table "restore_checkpoints", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "actor_membership_id"
    t.uuid "budget_workspace_id", null: false
    t.uuid "checkpoint_operation_id"
    t.datetime "created_at", null: false
    t.text "encrypted_payload", null: false
    t.string "encryption_version", default: "app-key-v1", null: false
    t.datetime "expires_at", null: false
    t.integer "lock_version", default: 0, null: false
    t.string "payload_checksum", null: false
    t.string "payload_format_version", null: false
    t.datetime "restored_at"
    t.jsonb "result_counts", default: {}, null: false
    t.jsonb "selected_scopes", default: [], null: false
    t.string "state", default: "ready", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_membership_id"], name: "index_restore_checkpoints_on_actor_membership_id"
    t.index ["budget_workspace_id", "state", "created_at"], name: "idx_restore_checkpoints_workspace_state"
    t.index ["budget_workspace_id"], name: "index_restore_checkpoints_on_budget_workspace_id"
    t.index ["checkpoint_operation_id"], name: "index_restore_checkpoints_on_checkpoint_operation_id"
    t.index ["id", "budget_workspace_id"], name: "uidx_restore_checkpoints_id_workspace", unique: true
    t.check_constraint "(state::text = 'restored'::text) = (restored_at IS NOT NULL)", name: "restore_checkpoints_restored_at_coherent"
    t.check_constraint "lock_version >= 0", name: "restore_checkpoints_lock_version_nonnegative"
    t.check_constraint "payload_checksum::text ~ '^[0-9a-f]{64}$'::text", name: "restore_checkpoints_checksum_valid"
    t.check_constraint "state::text = ANY (ARRAY['ready'::character varying, 'restored'::character varying, 'expired'::character varying]::text[])", name: "restore_checkpoints_state_valid"
  end

  create_table "subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account"
    t.boolean "active", default: true, null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.uuid "budget_workspace_id"
    t.datetime "created_at", null: false
    t.integer "due_day", default: 1, null: false
    t.uuid "linked_account_id"
    t.integer "lock_version", default: 0, null: false
    t.string "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["active"], name: "index_subscriptions_on_active"
    t.index ["budget_workspace_id"], name: "index_subscriptions_on_budget_workspace_id"
    t.index ["linked_account_id"], name: "index_subscriptions_on_linked_account_id"
    t.index ["user_id", "due_day", "name"], name: "index_subscriptions_on_user_due_day_name"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
    t.check_constraint "amount > 0::numeric", name: "subscriptions_amount_positive"
    t.check_constraint "due_day >= 1 AND due_day <= 31", name: "subscriptions_due_day_valid"
    t.check_constraint "lock_version >= 0", name: "subscriptions_lock_version_nonnegative"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "access_state", default: 0, null: false
    t.datetime "created_at", null: false
    t.string "default_landing_page", default: "overview", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "financial_rhythm", default: "steady_income", null: false
    t.string "last_seen_release_version"
    t.datetime "locked_at"
    t.string "preferred_month_view", default: "timeline", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.index ["access_state"], name: "index_users_on_access_state"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["locked_at"], name: "index_users_on_locked_at"
    t.index ["remember_created_at"], name: "index_users_on_remember_created_at"
    t.index ["reset_password_sent_at"], name: "index_users_on_reset_password_sent_at"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
    t.check_constraint "access_state >= 0 AND access_state <= 1", name: "users_access_state_valid"
    t.check_constraint "default_landing_page::text = ANY (ARRAY['overview'::character varying, 'months'::character varying, 'planning_templates'::character varying, 'accounts'::character varying, 'settings'::character varying]::text[])", name: "users_landing_page_valid"
    t.check_constraint "failed_attempts >= 0", name: "users_failed_attempts_nonnegative"
    t.check_constraint "financial_rhythm::text = ANY (ARRAY['steady_income'::character varying, 'variable_income'::character varying, 'shared_household'::character varying, 'debt_payoff'::character varying]::text[])", name: "users_financial_rhythm_valid"
    t.check_constraint "preferred_month_view::text = ANY (ARRAY['timeline'::character varying, 'breakdown'::character varying, 'calendar'::character varying, 'entries'::character varying]::text[])", name: "users_month_view_valid"
  end

  create_table "workspace_memberships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "budget_workspace_id", null: false
    t.datetime "created_at", null: false
    t.datetime "joined_at"
    t.datetime "onboarding_completed_at"
    t.datetime "onboarding_dismissed_at"
    t.string "onboarding_version"
    t.datetime "recent_operations_dismissed_through_at"
    t.datetime "removed_at"
    t.string "role", default: "owner", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["budget_workspace_id", "user_id"], name: "uidx_memberships_workspace_user", unique: true
    t.index ["budget_workspace_id"], name: "index_workspace_memberships_on_budget_workspace_id"
    t.index ["id", "budget_workspace_id"], name: "uidx_memberships_id_workspace", unique: true
    t.index ["user_id"], name: "index_workspace_memberships_on_user_id"
    t.check_constraint "(status::text = 'removed'::text) = (removed_at IS NOT NULL)", name: "memberships_removed_state_coherent"
    t.check_constraint "role::text = ANY (ARRAY['owner'::character varying, 'editor'::character varying, 'viewer'::character varying]::text[])", name: "memberships_role_valid"
    t.check_constraint "status::text = ANY (ARRAY['invited'::character varying, 'active'::character varying, 'suspended'::character varying, 'removed'::character varying]::text[])", name: "memberships_status_valid"
  end

  add_foreign_key "account_activities", "account_activity_imports"
  add_foreign_key "account_activities", "account_activity_imports", column: ["account_activity_import_id", "user_id", "account_id"], primary_key: ["id", "user_id", "account_id"], name: "fk_activities_import_scope"
  add_foreign_key "account_activities", "accounts"
  add_foreign_key "account_activities", "accounts", column: ["account_id", "user_id"], primary_key: ["id", "user_id"], name: "fk_activities_account_owner"
  add_foreign_key "account_activities", "budget_workspaces", validate: false
  add_foreign_key "account_activities", "expense_entries"
  add_foreign_key "account_activities", "expense_entries", column: ["expense_entry_id", "user_id"], primary_key: ["id", "user_id"], name: "fk_activities_entry_owner"
  add_foreign_key "account_activities", "users"
  add_foreign_key "account_activity_import_drafts", "accounts"
  add_foreign_key "account_activity_import_drafts", "accounts", column: ["account_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"], name: "fk_activity_import_drafts_account_workspace"
  add_foreign_key "account_activity_import_drafts", "accounts", column: ["account_id", "user_id"], primary_key: ["id", "user_id"], name: "fk_activity_import_drafts_account_owner"
  add_foreign_key "account_activity_import_drafts", "budget_workspaces"
  add_foreign_key "account_activity_import_drafts", "operation_runs", column: ["operation_run_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"], name: "fk_activity_import_drafts_operation_workspace"
  add_foreign_key "account_activity_import_drafts", "users"
  add_foreign_key "account_activity_imports", "accounts"
  add_foreign_key "account_activity_imports", "accounts", column: ["account_id", "user_id"], primary_key: ["id", "user_id"], name: "fk_activity_imports_account_owner"
  add_foreign_key "account_activity_imports", "budget_workspaces", validate: false
  add_foreign_key "account_activity_imports", "users"
  add_foreign_key "account_postings", "accounts", column: ["account_id", "budget_workspace_id", "currency_code"], primary_key: ["id", "budget_workspace_id", "currency_code"], name: "fk_postings_account_currency"
  add_foreign_key "account_postings", "accounts", column: ["account_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "account_postings", "budget_workspaces"
  add_foreign_key "account_postings", "budget_workspaces", column: ["budget_workspace_id", "currency_code"], primary_key: ["id", "default_currency_code"], name: "fk_account_postings_workspace_currency"
  add_foreign_key "account_postings", "financial_transactions", column: ["financial_transaction_id", "budget_workspace_id", "currency_code"], primary_key: ["id", "budget_workspace_id", "currency_code"], name: "fk_postings_transaction_currency"
  add_foreign_key "account_postings", "financial_transactions", column: ["financial_transaction_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "account_snapshots", "accounts"
  add_foreign_key "accounts", "budget_workspaces", column: ["budget_workspace_id", "currency_code"], primary_key: ["id", "default_currency_code"], name: "fk_accounts_workspace_currency"
  add_foreign_key "accounts", "budget_workspaces", validate: false
  add_foreign_key "accounts", "users"
  add_foreign_key "admin_audit_logs", "admin_users"
  add_foreign_key "admin_audit_logs", "users", column: "target_user_id"
  add_foreign_key "audit_events", "admin_users", column: "actor_admin_user_id"
  add_foreign_key "audit_events", "budget_workspaces"
  add_foreign_key "audit_events", "operation_runs", column: ["operation_run_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "audit_events", "users", column: "actor_user_id"
  add_foreign_key "audit_events", "workspace_memberships", column: ["actor_membership_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "backup_export_artifacts", "budget_workspaces"
  add_foreign_key "backup_export_artifacts", "data_transfer_runs", column: ["data_transfer_run_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"], name: "fk_backup_export_artifacts_transfer_workspace"
  add_foreign_key "backup_export_artifacts", "operation_runs", column: ["operation_run_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"], name: "fk_backup_export_artifacts_operation_workspace"
  add_foreign_key "backup_export_artifacts", "users"
  add_foreign_key "backup_restore_drafts", "budget_workspaces"
  add_foreign_key "backup_restore_drafts", "data_transfer_runs", column: ["data_transfer_run_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"], name: "fk_backup_restore_drafts_transfer_workspace"
  add_foreign_key "backup_restore_drafts", "operation_runs", column: ["operation_run_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"], name: "fk_backup_restore_drafts_operation_workspace"
  add_foreign_key "backup_restore_drafts", "restore_checkpoints", column: ["restore_checkpoint_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"], name: "fk_backup_restore_drafts_checkpoint_workspace"
  add_foreign_key "backup_restore_drafts", "users"
  add_foreign_key "balance_observations", "accounts", column: ["account_id", "budget_workspace_id", "currency_code"], primary_key: ["id", "budget_workspace_id", "currency_code"], name: "fk_observations_account_currency"
  add_foreign_key "balance_observations", "accounts", column: ["account_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "balance_observations", "budget_workspaces"
  add_foreign_key "balance_observations", "budget_workspaces", column: ["budget_workspace_id", "currency_code"], primary_key: ["id", "default_currency_code"], name: "fk_balance_observations_workspace_currency"
  add_foreign_key "balance_observations", "import_batches", column: ["source_import_batch_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "balance_observations", "import_rows", column: ["source_import_row_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "balance_observations", "workspace_memberships", column: ["actor_membership_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "budget_allocations", "budget_items", column: ["budget_item_id", "budget_workspace_id", "currency_code"], primary_key: ["id", "budget_workspace_id", "currency_code"], name: "fk_allocations_item_currency"
  add_foreign_key "budget_allocations", "budget_items", column: ["budget_item_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "budget_allocations", "budget_workspaces"
  add_foreign_key "budget_allocations", "budget_workspaces", column: ["budget_workspace_id", "currency_code"], primary_key: ["id", "default_currency_code"], name: "fk_budget_allocations_workspace_currency"
  add_foreign_key "budget_allocations", "financial_transactions", column: ["financial_transaction_id", "budget_workspace_id", "currency_code"], primary_key: ["id", "budget_workspace_id", "currency_code"], name: "fk_allocations_transaction_currency"
  add_foreign_key "budget_allocations", "financial_transactions", column: ["financial_transaction_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "budget_allocations", "workspace_memberships", column: ["matched_by_membership_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "budget_items", "accounts", column: ["intended_destination_account_id", "budget_workspace_id", "currency_code"], primary_key: ["id", "budget_workspace_id", "currency_code"], name: "fk_items_destination_account_currency"
  add_foreign_key "budget_items", "accounts", column: ["intended_destination_account_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "budget_items", "accounts", column: ["intended_source_account_id", "budget_workspace_id", "currency_code"], primary_key: ["id", "budget_workspace_id", "currency_code"], name: "fk_items_source_account_currency"
  add_foreign_key "budget_items", "accounts", column: ["intended_source_account_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "budget_items", "budget_periods", column: ["budget_period_id", "budget_workspace_id", "currency_code"], primary_key: ["id", "budget_workspace_id", "currency_code"], name: "fk_items_period_currency"
  add_foreign_key "budget_items", "budget_periods", column: ["budget_period_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "budget_items", "budget_workspaces"
  add_foreign_key "budget_items", "budget_workspaces", column: ["budget_workspace_id", "currency_code"], primary_key: ["id", "default_currency_code"], name: "fk_budget_items_workspace_currency"
  add_foreign_key "budget_items", "categories", column: ["category_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "budget_items", "recurring_occurrences", column: ["recurring_occurrence_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "budget_months", "budget_workspaces", validate: false
  add_foreign_key "budget_months", "users"
  add_foreign_key "budget_periods", "budget_workspaces"
  add_foreign_key "budget_periods", "budget_workspaces", column: ["budget_workspace_id", "currency_code"], primary_key: ["id", "default_currency_code"], name: "fk_budget_periods_workspace_currency"
  add_foreign_key "budget_workspaces", "users", column: "legacy_owner_user_id"
  add_foreign_key "categories", "budget_workspaces"
  add_foreign_key "credit_card_payment_policies", "accounts", column: ["liability_account_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "credit_card_payment_policies", "accounts", column: ["payment_account_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "credit_card_payment_policies", "budget_workspaces"
  add_foreign_key "credit_card_payment_policies", "planning_templates"
  add_foreign_key "credit_card_payment_policies", "planning_templates", column: ["planning_template_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "credit_cards", "accounts", column: "linked_account_id"
  add_foreign_key "credit_cards", "accounts", column: "payment_account_id"
  add_foreign_key "credit_cards", "accounts", column: ["linked_account_id", "user_id"], primary_key: ["id", "user_id"], name: "fk_credit_cards_linked_account_owner"
  add_foreign_key "credit_cards", "accounts", column: ["payment_account_id", "user_id"], primary_key: ["id", "user_id"], name: "fk_credit_cards_payment_account_owner"
  add_foreign_key "credit_cards", "budget_workspaces", validate: false
  add_foreign_key "credit_cards", "users"
  add_foreign_key "data_transfer_runs", "budget_workspaces"
  add_foreign_key "data_transfer_runs", "operation_runs", column: ["operation_run_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "data_transfer_runs", "workspace_memberships", column: ["actor_membership_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "expense_entries", "accounts", column: "destination_account_id"
  add_foreign_key "expense_entries", "accounts", column: "source_account_id"
  add_foreign_key "expense_entries", "accounts", column: ["destination_account_id", "user_id"], primary_key: ["id", "user_id"], name: "fk_entries_destination_account_owner"
  add_foreign_key "expense_entries", "accounts", column: ["source_account_id", "user_id"], primary_key: ["id", "user_id"], name: "fk_entries_source_account_owner"
  add_foreign_key "expense_entries", "budget_months"
  add_foreign_key "expense_entries", "budget_months", column: ["budget_month_id", "user_id"], primary_key: ["id", "user_id"], name: "fk_entries_month_owner"
  add_foreign_key "expense_entries", "budget_workspaces", validate: false
  add_foreign_key "expense_entries", "users"
  add_foreign_key "financial_transactions", "budget_workspaces"
  add_foreign_key "financial_transactions", "budget_workspaces", column: ["budget_workspace_id", "currency_code"], primary_key: ["id", "default_currency_code"], name: "fk_financial_transactions_workspace_currency"
  add_foreign_key "financial_transactions", "categories", column: ["category_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "financial_transactions", "financial_transactions", column: ["reversal_transaction_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "financial_transactions", "import_rows", column: ["import_row_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "import_batches", "accounts", column: ["account_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "import_batches", "budget_workspaces"
  add_foreign_key "import_batches", "import_profiles", column: ["import_profile_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "import_batches", "operation_runs", column: ["operation_run_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "import_batches", "workspace_memberships", column: ["actor_membership_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "import_profiles", "accounts", column: ["account_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "import_profiles", "budget_workspaces"
  add_foreign_key "import_rows", "budget_workspaces"
  add_foreign_key "import_rows", "financial_transactions", column: ["financial_transaction_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "import_rows", "import_batches", column: ["import_batch_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "legacy_record_mappings", "budget_workspaces"
  add_foreign_key "migration_discrepancies", "budget_workspaces"
  add_foreign_key "migration_discrepancies", "operation_runs", column: ["operation_run_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "month_close_item_snapshots", "budget_items"
  add_foreign_key "month_close_item_snapshots", "budget_items", column: ["budget_item_id", "budget_workspace_id", "currency_code"], primary_key: ["id", "budget_workspace_id", "currency_code"], name: "fk_close_item_snapshots_item_currency"
  add_foreign_key "month_close_item_snapshots", "budget_workspaces"
  add_foreign_key "month_close_item_snapshots", "month_closes"
  add_foreign_key "month_close_item_snapshots", "month_closes", column: ["month_close_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"], name: "fk_close_item_snapshots_close_workspace"
  add_foreign_key "month_close_transaction_snapshots", "budget_workspaces"
  add_foreign_key "month_close_transaction_snapshots", "financial_transactions"
  add_foreign_key "month_close_transaction_snapshots", "financial_transactions", column: ["financial_transaction_id", "budget_workspace_id", "currency_code"], primary_key: ["id", "budget_workspace_id", "currency_code"], name: "fk_close_transaction_snapshots_transaction_currency"
  add_foreign_key "month_close_transaction_snapshots", "month_closes"
  add_foreign_key "month_close_transaction_snapshots", "month_closes", column: ["month_close_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"], name: "fk_close_transaction_snapshots_close_workspace"
  add_foreign_key "month_closes", "budget_periods", column: ["budget_period_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "month_closes", "budget_workspaces"
  add_foreign_key "month_closes", "month_closes", column: ["reopens_month_close_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "month_closes", "operation_runs", column: ["close_operation_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "month_closes", "workspace_memberships", column: ["closed_by_membership_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "monthly_bills", "accounts", column: "linked_account_id"
  add_foreign_key "monthly_bills", "accounts", column: ["linked_account_id", "user_id"], primary_key: ["id", "user_id"], name: "fk_monthly_bills_account_owner"
  add_foreign_key "monthly_bills", "budget_workspaces", validate: false
  add_foreign_key "monthly_bills", "users"
  add_foreign_key "operation_runs", "budget_workspaces"
  add_foreign_key "operation_runs", "workspace_memberships", column: ["actor_membership_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "pay_schedules", "accounts", column: "linked_account_id"
  add_foreign_key "pay_schedules", "accounts", column: ["linked_account_id", "user_id"], primary_key: ["id", "user_id"], name: "fk_pay_schedules_account_owner"
  add_foreign_key "pay_schedules", "budget_workspaces", validate: false
  add_foreign_key "pay_schedules", "users"
  add_foreign_key "payment_plan_terms", "planning_templates"
  add_foreign_key "payment_plans", "accounts", column: "linked_account_id"
  add_foreign_key "payment_plans", "accounts", column: ["linked_account_id", "user_id"], primary_key: ["id", "user_id"], name: "fk_payment_plans_account_owner"
  add_foreign_key "payment_plans", "budget_workspaces", validate: false
  add_foreign_key "payment_plans", "users"
  add_foreign_key "planning_templates", "accounts", column: ["destination_account_id", "budget_workspace_id", "currency_code"], primary_key: ["id", "budget_workspace_id", "currency_code"], name: "fk_templates_destination_account_currency"
  add_foreign_key "planning_templates", "accounts", column: ["destination_account_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "planning_templates", "accounts", column: ["source_account_id", "budget_workspace_id", "currency_code"], primary_key: ["id", "budget_workspace_id", "currency_code"], name: "fk_templates_source_account_currency"
  add_foreign_key "planning_templates", "accounts", column: ["source_account_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "planning_templates", "budget_workspaces"
  add_foreign_key "planning_templates", "budget_workspaces", column: ["budget_workspace_id", "currency_code"], primary_key: ["id", "default_currency_code"], name: "fk_planning_templates_workspace_currency"
  add_foreign_key "planning_templates", "categories", column: ["category_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "recurrence_months", "recurrence_rules"
  add_foreign_key "recurrence_rules", "planning_templates"
  add_foreign_key "recurring_occurrences", "budget_items", column: ["budget_item_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "recurring_occurrences", "budget_periods", column: ["budget_period_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "recurring_occurrences", "budget_workspaces"
  add_foreign_key "recurring_occurrences", "operation_runs", column: ["generation_operation_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "recurring_occurrences", "planning_templates", column: ["planning_template_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"]
  add_foreign_key "restore_checkpoints", "budget_workspaces"
  add_foreign_key "restore_checkpoints", "operation_runs", column: "checkpoint_operation_id"
  add_foreign_key "restore_checkpoints", "operation_runs", column: ["checkpoint_operation_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"], name: "fk_restore_checkpoints_operation_workspace"
  add_foreign_key "restore_checkpoints", "workspace_memberships", column: "actor_membership_id"
  add_foreign_key "restore_checkpoints", "workspace_memberships", column: ["actor_membership_id", "budget_workspace_id"], primary_key: ["id", "budget_workspace_id"], name: "fk_restore_checkpoints_membership_workspace"
  add_foreign_key "subscriptions", "accounts", column: "linked_account_id"
  add_foreign_key "subscriptions", "accounts", column: ["linked_account_id", "user_id"], primary_key: ["id", "user_id"], name: "fk_subscriptions_account_owner"
  add_foreign_key "subscriptions", "budget_workspaces", validate: false
  add_foreign_key "subscriptions", "users"
  add_foreign_key "workspace_memberships", "budget_workspaces"
  add_foreign_key "workspace_memberships", "users"
end
