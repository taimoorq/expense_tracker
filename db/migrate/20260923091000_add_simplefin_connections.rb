class AddSimplefinConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :bank_connections, id: :uuid do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :actor_membership, type: :uuid, null: false, foreign_key: { to_table: :workspace_memberships }
      t.string :name, null: false, default: "SimpleFIN"
      t.string :status, null: false, default: "connecting"
      t.text :encrypted_access_url
      t.string :claim_fingerprint, null: false
      t.integer :credential_generation, null: false, default: 0
      t.boolean :automatic_refresh, null: false, default: false
      t.datetime :last_checked_at, :next_refresh_at
      t.jsonb :request_times, null: false, default: []
      t.string :error_message
      t.timestamps
      t.index [ :budget_workspace_id, :claim_fingerprint ], unique: true, name: "index_bank_connections_on_claim"
      t.index [ :id, :budget_workspace_id ], unique: true
      t.check_constraint "status IN ('connecting','active','needs_attention','disconnected')", name: "bank_connections_status"
    end
    create_table :bank_refreshes, id: :uuid do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :bank_connection, type: :uuid, null: false, foreign_key: true
      t.references :operation_run, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.integer :credential_generation, :workspace_epoch, null: false
      t.integer :attempts, null: false, default: 0
      t.string :state, null: false, default: "pending"
      t.boolean :include_transactions, null: false, default: false
      t.datetime :started_at, :completed_at, :lease_expires_at
      t.string :lease_token
      t.jsonb :results, null: false, default: {}
      t.jsonb :errors, null: false, default: []
      t.timestamps
      t.index :bank_connection_id, unique: true, where: "state IN ('pending','running')", name: "one_open_bank_refresh"
      t.index [ :id, :budget_workspace_id ], unique: true
      t.check_constraint "state IN ('pending','running','succeeded','partial','failed','cancelled')", name: "bank_refreshes_state"
    end
    create_table :connected_accounts, id: :uuid do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :bank_connection, type: :uuid, null: false, foreign_key: true
      t.references :account, type: :uuid, foreign_key: true
      t.string :provider_connection_id, :provider_account_id, :name, :institution_name, :currency, null: false
      t.string :state, null: false, default: "discovered"
      t.integer :sign_multiplier, null: false, default: 1
      t.integer :mapping_version, null: false, default: 0
      t.boolean :use_bank_balance, :import_transactions, null: false, default: false
      t.datetime :last_seen_at, :last_checked_at, :transactions_through_at
      t.string :error_message
      t.timestamps
      t.index [ :bank_connection_id, :provider_connection_id, :provider_account_id ], unique: true, name: "connected_account_provider_identity"
      t.index :account_id, unique: true, where: "account_id IS NOT NULL", name: "one_connection_per_account"
      t.index [ :id, :budget_workspace_id ], unique: true
      t.check_constraint "sign_multiplier IN (-1,1)", name: "connected_accounts_sign"
      t.check_constraint "state IN ('discovered','mapped','ignored','missing')", name: "connected_accounts_state"
    end
    create_table :provider_balances, id: :uuid do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :connected_account, type: :uuid, null: false, foreign_key: true
      t.references :bank_refresh, type: :uuid, foreign_key: true
      t.decimal :balance, :available_balance, precision: 19, scale: 4
      t.string :currency, :content_digest, null: false
      t.datetime :reported_at, :fetched_at, null: false
      t.string :state, null: false, default: "reported"
      t.timestamps
      t.index [ :connected_account_id, :reported_at, :content_digest ], unique: true, name: "provider_balance_revision"
      t.index [ :id, :budget_workspace_id ], unique: true
      t.check_constraint "state IN ('reported','accepted','disputed')", name: "provider_balances_state"
      t.check_constraint "balance IS NOT NULL AND reported_at <= fetched_at", name: "provider_balances_valid"
    end
    create_table :provider_transactions, id: :uuid do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :connected_account, type: :uuid, null: false, foreign_key: true
      t.references :financial_transaction, type: :uuid, foreign_key: true
      t.references :expense_entry, type: :uuid, foreign_key: true
      t.string :provider_id, :content_digest, :currency, :description, null: false
      t.decimal :amount, precision: 19, scale: 4, null: false
      t.datetime :transacted_at, :posted_at
      t.boolean :pending, null: false, default: false
      t.string :state, null: false, default: "review"
      t.jsonb :previous_revisions, null: false, default: []
      t.datetime :fetched_at, null: false
      t.timestamps
      t.index [ :connected_account_id, :provider_id ], unique: true
      t.index [ :id, :budget_workspace_id ], unique: true
      t.check_constraint "state IN ('review','accepted','ignored','changed')", name: "provider_transactions_state"
    end
    create_table :payment_commitments, id: :uuid do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :expense_entry, type: :uuid, foreign_key: true
      t.references :account, type: :uuid, null: false, foreign_key: true
      t.references :destination_account, type: :uuid, foreign_key: { to_table: :accounts }
      t.references :included_provider_balance, type: :uuid, foreign_key: { to_table: :provider_balances }
      t.decimal :amount, precision: 19, scale: 4, null: false
      t.string :currency_code, null: false
      t.date :initiated_on, null: false
      t.datetime :initiated_at, :reserved_at
      t.string :state, null: false, default: "reserved"
      t.timestamps
      t.index :expense_entry_id, unique: true, where: "state = 'reserved'", name: "one_active_entry_commitment"
      t.index [ :id, :budget_workspace_id ], unique: true
      t.check_constraint "amount > 0 AND state IN ('reserved','settled','cancelled')", name: "payment_commitments_valid"
    end
    create_table :payment_settlements, id: :uuid do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :payment_commitment, type: :uuid, null: false, foreign_key: true
      t.references :financial_transaction, type: :uuid, null: false, foreign_key: true
      t.decimal :amount, precision: 19, scale: 4, null: false
      t.timestamps
      t.index [ :payment_commitment_id, :financial_transaction_id ], unique: true, name: "payment_settlement_identity"
      t.check_constraint "amount > 0", name: "payment_settlement_positive"
    end
    add_reference :balance_observations, :provider_balance, type: :uuid, foreign_key: true
    remove_check_constraint :balance_observations, "source_kind IN ('manual','institution_file','migration','adjustment')", name: "observations_source_kind_valid"
    add_check_constraint :balance_observations, "source_kind IN ('manual','institution_file','migration','adjustment','bank_sync')", name: "observations_source_kind_valid"

    # A foreign ID from another workspace must fail even below the service layer.
    { bank_connections: { actor_membership: :workspace_memberships },
      bank_refreshes: { bank_connection: :bank_connections, operation_run: :operation_runs },
      connected_accounts: { bank_connection: :bank_connections, account: :accounts },
      provider_balances: { connected_account: :connected_accounts, bank_refresh: :bank_refreshes },
      provider_transactions: { connected_account: :connected_accounts, financial_transaction: :financial_transactions },
      payment_commitments: { account: :accounts, destination_account: :accounts, included_provider_balance: :provider_balances },
      payment_settlements: { payment_commitment: :payment_commitments, financial_transaction: :financial_transactions },
      balance_observations: { provider_balance: :provider_balances } }.each do |table, references|
      references.each do |reference, target|
        add_foreign_key table, target, column: [ "#{reference}_id", :budget_workspace_id ], primary_key: [ :id, :budget_workspace_id ]
      end
    end
  end
end
