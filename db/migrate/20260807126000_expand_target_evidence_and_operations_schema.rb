class ExpandTargetEvidenceAndOperationsSchema < ActiveRecord::Migration[8.1]
  def change
    create_operation_runs
    create_import_profiles
    create_import_batches
    create_import_rows
    create_audit_events
    create_data_transfer_runs
    create_migration_tracking
    add_cross_context_links
    add_evidence_ownership_constraints
  end

  private

  def create_operation_runs
    create_table :operation_runs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :actor_membership, type: :uuid
      t.string :operation_type, null: false
      t.string :idempotency_key, null: false
      t.string :request_digest, null: false
      t.jsonb :redacted_parameters, null: false, default: {}
      t.string :state, null: false, default: "pending"
      t.jsonb :result_counts, null: false, default: {}
      t.string :error_code
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index %i[id budget_workspace_id], unique: true, name: "uidx_operations_id_workspace"
      t.index %i[budget_workspace_id operation_type idempotency_key], unique: true, name: "uidx_operations_workspace_type_key"
      t.index %i[budget_workspace_id state created_at], name: "index_operations_on_workspace_state_created"
      t.check_constraint "request_digest ~ '^[0-9a-f]{64}$'", name: "operations_request_digest_valid"
      t.check_constraint "state IN ('pending', 'running', 'succeeded', 'failed', 'reversed')", name: "operations_state_valid"
      t.check_constraint "state NOT IN ('succeeded', 'failed', 'reversed') OR completed_at IS NOT NULL", name: "operations_completion_coherent"
      t.check_constraint "lock_version >= 0", name: "operations_lock_version_nonnegative"
    end
  end

  def create_import_profiles
    create_table :import_profiles, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid
      t.string :name, null: false
      t.string :parser_name, null: false
      t.string :parser_version, null: false
      t.integer :header_row_number, null: false, default: 1
      t.jsonb :column_mapping, null: false, default: {}
      t.string :amount_strategy, null: false
      t.string :fingerprint_version, null: false
      t.boolean :active, null: false, default: true
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index %i[id budget_workspace_id], unique: true, name: "uidx_import_profiles_id_workspace"
      t.index "budget_workspace_id, lower(name)", unique: true, name: "uidx_import_profiles_workspace_name"
      t.check_constraint "header_row_number > 0", name: "import_profiles_header_positive"
      t.check_constraint "amount_strategy IN ('charges_are_negative', 'charges_are_positive', 'type_column')", name: "import_profiles_amount_strategy_valid"
      t.check_constraint "lock_version >= 0", name: "import_profiles_lock_version_nonnegative"
    end
  end

  def create_import_batches
    create_table :import_batches, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid
      t.references :import_profile, type: :uuid
      t.references :operation_run, type: :uuid
      t.references :actor_membership, type: :uuid
      t.string :import_kind, null: false
      t.string :original_filename, null: false
      t.string :file_digest, null: false
      t.string :idempotency_key, null: false
      t.string :parser_version, null: false
      t.string :mapping_version, null: false
      t.string :fingerprint_version, null: false
      t.date :coverage_starts_on
      t.date :coverage_ends_on
      t.string :status, null: false, default: "previewed"
      t.integer :row_count, null: false, default: 0
      t.integer :imported_count, null: false, default: 0
      t.integer :duplicate_count, null: false, default: 0
      t.integer :error_count, null: false, default: 0
      t.jsonb :redacted_metadata, null: false, default: {}
      t.jsonb :warnings, null: false, default: []
      t.datetime :committed_at
      t.datetime :reverted_at
      t.datetime :failed_at
      t.string :failure_code
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index %i[id budget_workspace_id], unique: true, name: "uidx_import_batches_id_workspace"
      t.index %i[budget_workspace_id import_kind idempotency_key], unique: true, name: "uidx_import_batches_workspace_kind_key"
      t.index %i[budget_workspace_id status created_at], name: "index_import_batches_on_workspace_status_created"
      t.check_constraint "file_digest ~ '^[0-9a-f]{64}$'", name: "import_batches_digest_valid"
      t.check_constraint "status IN ('previewed', 'committing', 'committed', 'failed', 'reverting', 'reverted')", name: "import_batches_status_valid"
      t.check_constraint "import_kind IN ('account_activity', 'budget_plan', 'backup_restore')", name: "import_batches_kind_valid"
      t.check_constraint "row_count >= 0 AND imported_count >= 0 AND duplicate_count >= 0 AND error_count >= 0", name: "import_batches_counts_nonnegative"
      t.check_constraint "imported_count + duplicate_count + error_count <= row_count", name: "import_batches_counts_coherent"
      t.check_constraint "coverage_starts_on IS NULL OR coverage_ends_on IS NULL OR coverage_ends_on >= coverage_starts_on", name: "import_batches_coverage_valid"
      t.check_constraint "status <> 'committed' OR committed_at IS NOT NULL", name: "import_batches_commit_coherent"
      t.check_constraint "status <> 'reverted' OR reverted_at IS NOT NULL", name: "import_batches_revert_coherent"
      t.check_constraint "status <> 'failed' OR failed_at IS NOT NULL", name: "import_batches_failure_coherent"
      t.check_constraint "lock_version >= 0", name: "import_batches_lock_version_nonnegative"
    end
  end

  def create_import_rows
    create_table :import_rows, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :import_batch, type: :uuid, null: false
      t.integer :row_number, null: false
      t.string :provider_transaction_id
      t.string :fingerprint, null: false
      t.string :fingerprint_version, null: false
      t.jsonb :raw_payload, null: false, default: {}
      t.jsonb :normalized_payload, null: false, default: {}
      t.string :normalization_result, null: false
      t.string :status, null: false
      t.string :error_code
      t.text :error_message
      t.references :financial_transaction, type: :uuid
      t.timestamps

      t.index %i[id budget_workspace_id], unique: true, name: "uidx_import_rows_id_workspace"
      t.index %i[import_batch_id row_number], unique: true, name: "uidx_import_rows_batch_row"
      t.index %i[budget_workspace_id fingerprint_version fingerprint], name: "index_import_rows_on_workspace_fingerprint"
      t.check_constraint "row_number > 0", name: "import_rows_number_positive"
      t.check_constraint "normalization_result IN ('normalized', 'duplicate', 'invalid', 'unsupported')", name: "import_rows_normalization_valid"
      t.check_constraint "status IN ('accepted', 'duplicate', 'rejected', 'reversed')", name: "import_rows_status_valid"
      t.check_constraint "status <> 'rejected' OR error_code IS NOT NULL", name: "import_rows_rejection_coherent"
    end
  end

  def create_audit_events
    create_table :audit_events, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :actor_membership, type: :uuid
      t.references :actor_user, type: :uuid
      t.references :actor_admin_user, type: :uuid
      t.references :operation_run, type: :uuid
      t.string :entity_type, null: false
      t.uuid :entity_id, null: false
      t.string :action, null: false
      t.jsonb :changed_fields, null: false, default: {}
      t.string :correlation_id
      t.string :request_id
      t.string :source_ip
      t.text :user_agent
      t.datetime :event_at, null: false
      t.datetime :created_at, null: false

      t.index %i[id budget_workspace_id], unique: true, name: "uidx_audit_events_id_workspace"
      t.index %i[budget_workspace_id event_at], order: { event_at: :desc }, name: "index_audit_events_on_workspace_event"
      t.index %i[budget_workspace_id entity_type entity_id event_at], name: "index_audit_events_on_entity_event"
      t.check_constraint "action IN ('create', 'edit', 'void', 'reverse', 'archive', 'import', 'import_reversal', 'match', 'unmatch', 'generate', 'trust_observation', 'supersede_observation', 'close', 'reopen', 'backup_export', 'backup_restore', 'access_change')", name: "audit_events_action_valid"
    end
  end

  def create_data_transfer_runs
    create_table :data_transfer_runs, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :actor_membership, type: :uuid
      t.references :operation_run, type: :uuid
      t.string :operation, null: false
      t.string :payload_format_version, null: false
      t.string :envelope_version
      t.string :payload_checksum, null: false
      t.jsonb :selected_scopes, null: false, default: []
      t.string :state, null: false, default: "pending"
      t.jsonb :result_counts, null: false, default: {}
      t.string :checkpoint_reference
      t.string :error_code
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index %i[id budget_workspace_id], unique: true, name: "uidx_transfer_runs_id_workspace"
      t.index %i[budget_workspace_id operation created_at], name: "index_transfer_runs_on_workspace_operation"
      t.check_constraint "operation IN ('export', 'preview', 'restore')", name: "transfer_runs_operation_valid"
      t.check_constraint "payload_checksum ~ '^[0-9a-f]{64}$'", name: "transfer_runs_checksum_valid"
      t.check_constraint "state IN ('pending', 'running', 'succeeded', 'failed')", name: "transfer_runs_state_valid"
      t.check_constraint "state NOT IN ('succeeded', 'failed') OR completed_at IS NOT NULL", name: "transfer_runs_completion_coherent"
      t.check_constraint "lock_version >= 0", name: "transfer_runs_lock_version_nonnegative"
    end
  end

  def create_migration_tracking
    create_table :legacy_record_mappings, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.string :legacy_record_type, null: false
      t.uuid :legacy_record_id, null: false
      t.string :target_record_type, null: false
      t.uuid :target_record_id, null: false
      t.string :mapping_version, null: false
      t.string :source_checksum
      t.string :status, null: false, default: "mapped"
      t.jsonb :metadata, null: false, default: {}
      t.timestamps

      t.index %i[budget_workspace_id legacy_record_type legacy_record_id], unique: true, name: "uidx_legacy_mappings_source"
      t.index %i[budget_workspace_id target_record_type target_record_id], name: "index_legacy_mappings_target"
      t.check_constraint "source_checksum IS NULL OR source_checksum ~ '^[0-9a-f]{64}$'", name: "legacy_mappings_checksum_valid"
      t.check_constraint "status IN ('mapped', 'omitted', 'quarantined')", name: "legacy_mappings_status_valid"
    end

    create_table :migration_discrepancies, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :operation_run, type: :uuid
      t.string :legacy_record_type, null: false
      t.uuid :legacy_record_id, null: false
      t.string :code, null: false
      t.string :status, null: false, default: "open"
      t.jsonb :redacted_details, null: false, default: {}
      t.datetime :resolved_at
      t.timestamps

      t.index %i[budget_workspace_id status created_at], name: "index_migration_discrepancies_on_workspace_status"
      t.index %i[budget_workspace_id legacy_record_type legacy_record_id code], unique: true, name: "uidx_migration_discrepancies_source_code"
      t.check_constraint "status IN ('open', 'resolved', 'accepted')", name: "migration_discrepancies_status_valid"
      t.check_constraint "status = 'open' OR resolved_at IS NOT NULL", name: "migration_discrepancies_resolution_coherent"
    end
  end

  def add_cross_context_links
    add_column :financial_transactions, :import_row_id, :uuid
    add_index :financial_transactions, :import_row_id, unique: true, where: "import_row_id IS NOT NULL"

    add_column :balance_observations, :source_import_batch_id, :uuid
    add_column :balance_observations, :source_import_row_id, :uuid
    add_index :balance_observations, :source_import_batch_id
    add_index :balance_observations, :source_import_row_id

    add_column :recurring_occurrences, :generation_operation_id, :uuid
    add_index :recurring_occurrences, :generation_operation_id

    add_column :month_closes, :close_operation_id, :uuid
    add_index :month_closes, :close_operation_id
  end

  def add_evidence_ownership_constraints
    add_workspace_foreign_key :operation_runs, :workspace_memberships, :actor_membership_id
    add_workspace_foreign_key :import_profiles, :accounts, :account_id
    add_workspace_foreign_key :import_batches, :accounts, :account_id
    add_workspace_foreign_key :import_batches, :import_profiles, :import_profile_id
    add_workspace_foreign_key :import_batches, :operation_runs, :operation_run_id
    add_workspace_foreign_key :import_batches, :workspace_memberships, :actor_membership_id
    add_workspace_foreign_key :import_rows, :import_batches, :import_batch_id
    add_workspace_foreign_key :import_rows, :financial_transactions, :financial_transaction_id
    add_workspace_foreign_key :audit_events, :workspace_memberships, :actor_membership_id
    add_workspace_foreign_key :audit_events, :operation_runs, :operation_run_id
    add_workspace_foreign_key :data_transfer_runs, :workspace_memberships, :actor_membership_id
    add_workspace_foreign_key :data_transfer_runs, :operation_runs, :operation_run_id
    add_workspace_foreign_key :migration_discrepancies, :operation_runs, :operation_run_id
    add_workspace_foreign_key :financial_transactions, :import_rows, :import_row_id
    add_workspace_foreign_key :balance_observations, :import_batches, :source_import_batch_id
    add_workspace_foreign_key :balance_observations, :import_rows, :source_import_row_id
    add_workspace_foreign_key :recurring_occurrences, :operation_runs, :generation_operation_id
    add_workspace_foreign_key :month_closes, :operation_runs, :close_operation_id

    add_foreign_key :audit_events, :users, column: :actor_user_id
    add_foreign_key :audit_events, :admin_users, column: :actor_admin_user_id
  end

  def add_workspace_foreign_key(from_table, to_table, foreign_id)
    add_foreign_key from_table,
      to_table,
      column: [ foreign_id, :budget_workspace_id ],
      primary_key: %i[id budget_workspace_id]
  end
end
