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

ActiveRecord::Schema[8.1].define(version: 2026_03_14_130100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

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
    t.index ["user_id", "name"], name: "index_accounts_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_accounts_on_user_id"
  end

  create_table "budget_months", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.decimal "actual_income", precision: 12, scale: 2
    t.datetime "created_at", null: false
    t.string "label", null: false
    t.decimal "leftover", precision: 12, scale: 2
    t.date "month_on", null: false
    t.text "notes"
    t.decimal "planned_income", precision: 12, scale: 2
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id", "month_on"], name: "index_budget_months_on_user_id_and_month_on", unique: true
    t.index ["user_id"], name: "index_budget_months_on_user_id"
  end

  create_table "credit_cards", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.decimal "minimum_payment", precision: 12, scale: 2, default: "0.0", null: false
    t.string "name", null: false
    t.text "notes"
    t.integer "priority", default: 1, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["active"], name: "index_credit_cards_on_active"
    t.index ["priority"], name: "index_credit_cards_on_priority"
    t.index ["user_id"], name: "index_credit_cards_on_user_id"
  end

  create_table "expense_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account"
    t.decimal "actual_amount", precision: 12, scale: 2
    t.uuid "budget_month_id", null: false
    t.string "category"
    t.datetime "created_at", null: false
    t.string "need_or_want"
    t.text "notes"
    t.date "occurred_on"
    t.string "payee"
    t.decimal "planned_amount", precision: 12, scale: 2
    t.integer "section", default: 6, null: false
    t.string "source_file"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["budget_month_id"], name: "index_expense_entries_on_budget_month_id"
    t.index ["occurred_on"], name: "index_expense_entries_on_occurred_on"
    t.index ["section"], name: "index_expense_entries_on_section"
    t.index ["status"], name: "index_expense_entries_on_status"
    t.index ["user_id"], name: "index_expense_entries_on_user_id"
  end

  create_table "monthly_bills", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.decimal "default_amount", precision: 12, scale: 2
    t.integer "due_day", default: 1, null: false
    t.integer "kind", default: 0, null: false
    t.string "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["active"], name: "index_monthly_bills_on_active"
    t.index ["kind"], name: "index_monthly_bills_on_kind"
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
    t.date "first_pay_on", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.integer "weekend_adjustment", default: 1, null: false
    t.index ["active"], name: "index_pay_schedules_on_active"
    t.index ["cadence"], name: "index_pay_schedules_on_cadence"
    t.index ["user_id"], name: "index_pay_schedules_on_user_id"
  end

  create_table "payment_plans", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account"
    t.boolean "active", default: true, null: false
    t.decimal "amount_paid", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.integer "due_day", default: 15, null: false
    t.decimal "monthly_target", precision: 12, scale: 2
    t.string "name", null: false
    t.text "notes"
    t.decimal "total_due", precision: 12, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["active"], name: "index_payment_plans_on_active"
    t.index ["user_id"], name: "index_payment_plans_on_user_id"
  end

  create_table "subscriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "account"
    t.boolean "active", default: true, null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.integer "due_day", default: 1, null: false
    t.string "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["active"], name: "index_subscriptions_on_active"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "account_snapshots", "accounts"
  add_foreign_key "accounts", "users"
  add_foreign_key "budget_months", "users"
  add_foreign_key "credit_cards", "users"
  add_foreign_key "expense_entries", "budget_months"
  add_foreign_key "expense_entries", "users"
  add_foreign_key "monthly_bills", "users"
  add_foreign_key "pay_schedules", "users"
  add_foreign_key "payment_plans", "users"
  add_foreign_key "subscriptions", "users"
end
