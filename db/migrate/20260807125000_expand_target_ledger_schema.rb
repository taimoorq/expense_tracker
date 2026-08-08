class ExpandTargetLedgerSchema < ActiveRecord::Migration[8.1]
  def change
    create_financial_transactions
    create_account_postings
    create_budget_allocations
    create_balance_observations
    add_ledger_ownership_constraints
  end

  private

  def create_financial_transactions
    create_table :financial_transactions, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.date :effective_on, null: false
      t.date :posted_on
      t.string :description, null: false
      t.string :payee
      t.text :memo
      t.references :category, type: :uuid
      t.decimal :gross_amount, precision: 19, scale: 4, null: false
      t.string :currency_code, null: false, limit: 3
      t.string :flow_kind, null: false
      t.string :state, null: false, default: "posted"
      t.string :origin_kind, null: false
      t.string :provider_transaction_id
      t.string :idempotency_key
      t.references :reversal_transaction, type: :uuid
      t.datetime :voided_at
      t.string :void_reason
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index %i[id budget_workspace_id], unique: true, name: "uidx_transactions_id_workspace"
      t.index %i[budget_workspace_id effective_on], order: { effective_on: :desc }, name: "index_transactions_on_workspace_effective"
      t.index %i[budget_workspace_id provider_transaction_id],
        unique: true,
        where: "provider_transaction_id IS NOT NULL",
        name: "uidx_transactions_workspace_provider_id"
      t.index %i[budget_workspace_id idempotency_key],
        unique: true,
        where: "idempotency_key IS NOT NULL",
        name: "uidx_transactions_workspace_idempotency"
      t.check_constraint "gross_amount >= 0", name: "transactions_gross_nonnegative"
      t.check_constraint "currency_code ~ '^[A-Z]{3}$'", name: "transactions_currency_valid"
      t.check_constraint "flow_kind IN ('income', 'outflow', 'transfer', 'adjustment')", name: "transactions_flow_kind_valid"
      t.check_constraint "state IN ('pending', 'posted', 'voided', 'reversed')", name: "transactions_state_valid"
      t.check_constraint "origin_kind IN ('manual', 'institution_import', 'migration', 'system_adjustment')", name: "transactions_origin_valid"
      t.check_constraint "state = 'voided' OR (voided_at IS NULL AND void_reason IS NULL)", name: "transactions_void_coherent"
      t.check_constraint "reversal_transaction_id IS NULL OR state IN ('reversed', 'posted')", name: "transactions_reversal_coherent"
      t.check_constraint "lock_version >= 0", name: "transactions_lock_version_nonnegative"
    end
  end

  def create_account_postings
    create_table :account_postings, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :financial_transaction, type: :uuid, null: false
      t.references :account, type: :uuid, null: false
      t.decimal :amount, precision: 19, scale: 4, null: false
      t.string :currency_code, null: false, limit: 3
      t.string :role, null: false
      t.integer :sequence_number, null: false, default: 0
      t.timestamps

      t.index %i[id budget_workspace_id], unique: true, name: "uidx_postings_id_workspace"
      t.index %i[financial_transaction_id sequence_number], unique: true, name: "uidx_postings_transaction_sequence"
      t.index %i[account_id financial_transaction_id], name: "index_postings_on_account_transaction"
      t.check_constraint "amount <> 0", name: "postings_amount_nonzero"
      t.check_constraint "currency_code ~ '^[A-Z]{3}$'", name: "postings_currency_valid"
      t.check_constraint "role IN ('primary', 'source', 'destination', 'adjustment')", name: "postings_role_valid"
      t.check_constraint "sequence_number >= 0", name: "postings_sequence_nonnegative"
    end
  end

  def create_budget_allocations
    create_table :budget_allocations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :budget_item, type: :uuid, null: false
      t.references :financial_transaction, type: :uuid, null: false
      t.decimal :amount, precision: 19, scale: 4, null: false
      t.string :currency_code, null: false, limit: 3
      t.string :match_kind, null: false
      t.decimal :match_confidence, precision: 5, scale: 4
      t.references :matched_by_membership, type: :uuid
      t.datetime :matched_at, null: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index %i[id budget_workspace_id], unique: true, name: "uidx_allocations_id_workspace"
      t.index %i[budget_item_id financial_transaction_id], unique: true, name: "uidx_allocations_item_transaction"
      t.check_constraint "amount > 0", name: "allocations_amount_positive"
      t.check_constraint "currency_code ~ '^[A-Z]{3}$'", name: "allocations_currency_valid"
      t.check_constraint "match_kind IN ('manual', 'suggested', 'exact_import', 'migration')", name: "allocations_match_kind_valid"
      t.check_constraint "match_confidence IS NULL OR match_confidence BETWEEN 0 AND 1", name: "allocations_confidence_valid"
      t.check_constraint "lock_version >= 0", name: "allocations_lock_version_nonnegative"
    end
  end

  def create_balance_observations
    create_table :balance_observations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid, null: false
      t.datetime :observed_at, null: false
      t.datetime :effective_through_at, null: false
      t.decimal :balance, precision: 19, scale: 4, null: false
      t.decimal :available_balance, precision: 19, scale: 4
      t.string :currency_code, null: false, limit: 3
      t.string :source_kind, null: false
      t.references :actor_membership, type: :uuid
      t.string :status, null: false, default: "trusted"
      t.text :notes
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index %i[id budget_workspace_id], unique: true, name: "uidx_observations_id_workspace"
      t.index %i[account_id effective_through_at created_at],
        order: { effective_through_at: :desc, created_at: :desc },
        name: "index_observations_on_account_effective"
      t.check_constraint "observed_at >= effective_through_at", name: "observations_effective_window_valid"
      t.check_constraint "currency_code ~ '^[A-Z]{3}$'", name: "observations_currency_valid"
      t.check_constraint "source_kind IN ('manual', 'institution_file', 'migration', 'adjustment')", name: "observations_source_kind_valid"
      t.check_constraint "status IN ('trusted', 'superseded', 'disputed')", name: "observations_status_valid"
      t.check_constraint "lock_version >= 0", name: "observations_lock_version_nonnegative"
    end
  end

  def add_ledger_ownership_constraints
    add_workspace_foreign_key :financial_transactions, :categories, :category_id
    add_workspace_foreign_key :financial_transactions, :financial_transactions, :reversal_transaction_id
    add_workspace_foreign_key :account_postings, :financial_transactions, :financial_transaction_id
    add_workspace_foreign_key :account_postings, :accounts, :account_id
    add_workspace_foreign_key :budget_allocations, :budget_items, :budget_item_id
    add_workspace_foreign_key :budget_allocations, :financial_transactions, :financial_transaction_id
    add_workspace_foreign_key :budget_allocations, :workspace_memberships, :matched_by_membership_id
    add_workspace_foreign_key :balance_observations, :accounts, :account_id
    add_workspace_foreign_key :balance_observations, :workspace_memberships, :actor_membership_id
  end

  def add_workspace_foreign_key(from_table, to_table, foreign_id)
    add_foreign_key from_table,
      to_table,
      column: [ foreign_id, :budget_workspace_id ],
      primary_key: %i[id budget_workspace_id]
  end
end
