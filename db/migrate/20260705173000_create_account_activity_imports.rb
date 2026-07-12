class CreateAccountActivityImports < ActiveRecord::Migration[8.1]
  def change
    create_table :account_activity_imports, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.string :original_filename, null: false
      t.integer :header_row_number, null: false
      t.jsonb :column_mapping, default: {}, null: false
      t.string :amount_strategy, null: false
      t.integer :rows_count, default: 0, null: false
      t.integer :imported_count, default: 0, null: false
      t.integer :duplicate_count, default: 0, null: false
      t.jsonb :warning_messages, default: [], null: false
      t.date :started_on
      t.date :ended_on
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :account_activity_imports, [ :account_id, :created_at ], name: "index_account_activity_imports_on_account_recent", order: { created_at: :desc }
    add_index :account_activity_imports, [ :user_id, :account_id, :created_at ], name: "index_account_activity_imports_on_user_account_recent", order: { created_at: :desc }

    create_table :account_activities, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, null: false, type: :uuid, foreign_key: true
      t.references :account, null: false, type: :uuid, foreign_key: true
      t.references :account_activity_import, null: false, type: :uuid, foreign_key: true, index: { name: "index_account_activities_on_import_id" }
      t.references :expense_entry, type: :uuid, foreign_key: true
      t.date :transaction_on, null: false
      t.date :posted_on
      t.string :description, null: false
      t.string :category
      t.string :activity_type
      t.text :memo
      t.decimal :raw_amount, precision: 14, scale: 2, null: false
      t.decimal :amount, precision: 14, scale: 2, null: false
      t.decimal :account_delta, precision: 14, scale: 2, null: false
      t.integer :row_number, null: false
      t.string :fingerprint, null: false
      t.jsonb :raw_payload, default: {}, null: false

      t.timestamps
    end

    add_index :account_activities, [ :account_id, :fingerprint ], unique: true
    add_index :account_activities, [ :account_id, :transaction_on, :created_at ],
              name: "index_account_activities_on_account_chronological",
              order: { transaction_on: :desc, created_at: :desc }
    add_index :account_activities, [ :user_id, :account_id, :category ], name: "index_account_activities_on_user_account_category"
    add_index :account_activities, [ :user_id, :account_id, :activity_type ], name: "index_account_activities_on_user_account_activity_type"
  end
end
