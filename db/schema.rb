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

ActiveRecord::Schema[8.1].define(version: 2026_07_05_173000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "account_activities", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_activity_import_id", null: false
    t.decimal "account_delta", precision: 14, scale: 2, null: false
    t.uuid "account_id", null: false
    t.string "activity_type"
    t.decimal "amount", precision: 14, scale: 2, null: false
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
    t.index ["expense_entry_id"], name: "index_account_activities_on_expense_entry_id"
    t.index ["user_id", "account_id", "activity_type"], name: "index_account_activities_on_user_account_activity_type"
    t.index ["user_id", "account_id", "category"], name: "index_account_activities_on_user_account_category"
    t.index ["user_id"], name: "index_account_activities_on_user_id"
  end

  create_table "account_activity_imports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.string "amount_strategy", null: false
    t.jsonb "column_mapping", default: {}, null: false
    t.datetime "created_at", null: false
    t.integer "duplicate_count", default: 0, null: false
    t.date "ended_on"
    t.integer "header_row_number", null: false
    t.integer "imported_count", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "original_filename", null: false
    t.integer "rows_count", default: 0, null: false
    t.date "started_on"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.jsonb "warning_messages", default: [], null: false
    t.index ["account_id", "created_at"], name: "index_account_activity_imports_on_account_recent", order: { created_at: :desc }
    t.index ["account_id"], name: "index_account_activity_imports_on_account_id"
    t.index ["user_id", "account_id", "created_at"], name: "index_account_activity_imports_on_user_account_recent", order: { created_at: :desc }
    t.index ["user_id"], name: "index_account_activity_imports_on_user_id"
  end

  create_table "account_snapshots", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "account_id", null: false
    t.decimal "available_balance", precision: 14, scale: 2
    t.decimal "balance", precision: 14, scale: 2, null: false
    t.datetime "created_at", null: false
    t.text "notes"
    t.date "recorded_on", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "recorded_on"], name: "index_account_snapshots_on_account_id_and_recorded_on", unique: true
    t.index ["account_id"], name: "index_account_snapshots_on_account_id"
    t.index ["recorded_on"], name: "index_account_snapshots_on_recorded_on"
  end

  create_table "accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.boolean "include_in_cash", default: false, null: false
    t.boolean "include_in_net_worth", default: true, null: false
    t.string "institution_name"
    t.integer "kind", default: 0, null: false
    t.string "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["active"], name: "index_accounts_on_active"
    t.index ["kind"], name: "index_accounts_on_kind"
    t.index ["user_id", "active", "name"], name: "index_accounts_on_user_active_name", order: { active: :desc }
    t.index ["user_id", "name"], name: "index_accounts_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_accounts_on_user_id"
  end

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
  end

  create_table "budget_months", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "label", null: false
    t.decimal "leftover", precision: 12, scale: 2
    t.date "month_on", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id", "month_on"], name: "index_budget_months_on_user_id_and_month_on", unique: true
    t.index ["user_id"], name: "index_budget_months_on_user_id"
  end

  create_table "credit_cards", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.integer "due_day", default: 1, null: false
    t.uuid "linked_account_id"
    t.decimal "minimum_payment", precision: 12, scale: 2, default: "0.0", null: false
    t.string "name", null: false
    t.text "notes"
    t.uuid "payment_account_id"
    t.integer "priority", default: 1, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["active"], name: "index_credit_cards_on_active"
    t.index ["due_day"], name: "index_credit_cards_on_due_day"
    t.index ["linked_account_id"], name: "index_credit_cards_on_linked_account_id"
    t.index ["payment_account_id"], name: "index_credit_cards_on_payment_account_id"
    t.index ["priority"], name: "index_credit_cards_on_priority"
    t.index ["user_id", "priority", "name"], name: "index_credit_cards_on_user_priority_name"
    t.index ["user_id"], name: "index_credit_cards_on_user_id"
  end

  create_table "expense_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account"
    t.decimal "actual_amount", precision: 12, scale: 2
    t.datetime "auto_completed_at"
    t.uuid "budget_month_id", null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.uuid "destination_account_id"
    t.string "generated_entry_key"
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
    t.index ["destination_account_id", "occurred_on", "created_at"], name: "index_expense_entries_on_destination_account_recent", order: { occurred_on: :desc, created_at: :desc }, where: "(destination_account_id IS NOT NULL)"
    t.index ["destination_account_id"], name: "index_expense_entries_on_destination_account_id"
    t.index ["generated_entry_key"], name: "index_expense_entries_on_generated_entry_key_unique", unique: true, where: "(generated_entry_key IS NOT NULL)"
    t.index ["occurred_on"], name: "index_expense_entries_on_occurred_on"
    t.index ["section"], name: "index_expense_entries_on_section"
    t.index ["source_account_id", "occurred_on", "created_at"], name: "index_expense_entries_on_source_account_recent", order: { occurred_on: :desc, created_at: :desc }, where: "(source_account_id IS NOT NULL)"
    t.index ["source_account_id"], name: "index_expense_entries_on_source_account_id"
    t.index ["source_template_type", "source_template_id"], name: "index_expense_entries_on_source_template"
    t.index ["status"], name: "index_expense_entries_on_status"
    t.index ["user_id", "status", "occurred_on"], name: "index_expense_entries_on_user_due_recurring", where: "((occurred_on IS NOT NULL) AND ((source_file)::text = ANY ((ARRAY['pay_schedule'::character varying, 'subscription'::character varying, 'monthly_bill'::character varying, 'payment_plan'::character varying])::text[])))"
    t.index ["user_id"], name: "index_expense_entries_on_user_id"
  end

  create_table "monthly_bills", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account"
    t.boolean "active", default: true, null: false
    t.integer "billing_frequency", default: 0, null: false
    t.integer "billing_months", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.decimal "default_amount", precision: 12, scale: 2
    t.integer "due_day", default: 1, null: false
    t.integer "kind", default: 0, null: false
    t.uuid "linked_account_id"
    t.string "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["active"], name: "index_monthly_bills_on_active"
    t.index ["kind"], name: "index_monthly_bills_on_kind"
    t.index ["linked_account_id"], name: "index_monthly_bills_on_linked_account_id"
    t.index ["user_id", "kind", "due_day", "name"], name: "index_monthly_bills_on_user_kind_due_day_name"
    t.index ["user_id"], name: "index_monthly_bills_on_user_id"
  end

  create_table "pay_schedules", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account"
    t.boolean "active", default: true, null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.integer "cadence", default: 2, null: false
    t.datetime "created_at", null: false
    t.integer "day_of_month_one"
    t.integer "day_of_month_two"
    t.date "ends_on"
    t.date "first_pay_on", null: false
    t.uuid "linked_account_id"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.integer "weekend_adjustment", default: 1, null: false
    t.index ["active"], name: "index_pay_schedules_on_active"
    t.index ["cadence"], name: "index_pay_schedules_on_cadence"
    t.index ["linked_account_id"], name: "index_pay_schedules_on_linked_account_id"
    t.index ["user_id", "active", "first_pay_on", "ends_on"], name: "index_pay_schedules_on_user_active_date_window"
    t.index ["user_id", "name"], name: "index_pay_schedules_on_user_name"
    t.index ["user_id"], name: "index_pay_schedules_on_user_id"
  end

  create_table "payment_plans", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account"
    t.boolean "active", default: true, null: false
    t.decimal "amount_paid", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.integer "due_day", default: 15, null: false
    t.uuid "linked_account_id"
    t.decimal "monthly_target", precision: 12, scale: 2
    t.string "name", null: false
    t.text "notes"
    t.decimal "total_due", precision: 12, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["active"], name: "index_payment_plans_on_active"
    t.index ["linked_account_id"], name: "index_payment_plans_on_linked_account_id"
    t.index ["user_id", "due_day", "name"], name: "index_payment_plans_on_user_due_day_name"
    t.index ["user_id"], name: "index_payment_plans_on_user_id"
  end

  create_table "subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account"
    t.boolean "active", default: true, null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.integer "due_day", default: 1, null: false
    t.uuid "linked_account_id"
    t.string "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["active"], name: "index_subscriptions_on_active"
    t.index ["linked_account_id"], name: "index_subscriptions_on_linked_account_id"
    t.index ["user_id", "due_day", "name"], name: "index_subscriptions_on_user_due_day_name"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
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
  end

  add_foreign_key "account_activities", "account_activity_imports"
  add_foreign_key "account_activities", "accounts"
  add_foreign_key "account_activities", "expense_entries"
  add_foreign_key "account_activities", "users"
  add_foreign_key "account_activity_imports", "accounts"
  add_foreign_key "account_activity_imports", "users"
  add_foreign_key "account_snapshots", "accounts"
  add_foreign_key "accounts", "users"
  add_foreign_key "admin_audit_logs", "admin_users"
  add_foreign_key "admin_audit_logs", "users", column: "target_user_id"
  add_foreign_key "budget_months", "users"
  add_foreign_key "credit_cards", "accounts", column: "linked_account_id"
  add_foreign_key "credit_cards", "accounts", column: "payment_account_id"
  add_foreign_key "credit_cards", "users"
  add_foreign_key "expense_entries", "accounts", column: "destination_account_id"
  add_foreign_key "expense_entries", "accounts", column: "source_account_id"
  add_foreign_key "expense_entries", "budget_months"
  add_foreign_key "expense_entries", "users"
  add_foreign_key "monthly_bills", "accounts", column: "linked_account_id"
  add_foreign_key "monthly_bills", "users"
  add_foreign_key "pay_schedules", "accounts", column: "linked_account_id"
  add_foreign_key "pay_schedules", "users"
  add_foreign_key "payment_plans", "accounts", column: "linked_account_id"
  add_foreign_key "payment_plans", "users"
  add_foreign_key "subscriptions", "accounts", column: "linked_account_id"
  add_foreign_key "subscriptions", "users"
end
