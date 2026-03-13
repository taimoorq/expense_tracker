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

ActiveRecord::Schema[8.1].define(version: 2026_03_13_000007) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "budget_months", force: :cascade do |t|
    t.decimal "actual_income", precision: 12, scale: 2
    t.datetime "created_at", null: false
    t.string "label", null: false
    t.decimal "leftover", precision: 12, scale: 2
    t.date "month_on", null: false
    t.text "notes"
    t.decimal "planned_income", precision: 12, scale: 2
    t.datetime "updated_at", null: false
    t.index ["month_on"], name: "index_budget_months_on_month_on", unique: true
  end

  create_table "credit_cards", force: :cascade do |t|
    t.string "account"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.decimal "minimum_payment", precision: 12, scale: 2, default: "0.0", null: false
    t.string "name", null: false
    t.text "notes"
    t.integer "priority", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_credit_cards_on_active"
    t.index ["priority"], name: "index_credit_cards_on_priority"
  end

  create_table "expense_entries", force: :cascade do |t|
    t.string "account"
    t.decimal "actual_amount", precision: 12, scale: 2
    t.bigint "budget_month_id", null: false
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
    t.index ["budget_month_id"], name: "index_expense_entries_on_budget_month_id"
    t.index ["occurred_on"], name: "index_expense_entries_on_occurred_on"
    t.index ["section"], name: "index_expense_entries_on_section"
    t.index ["status"], name: "index_expense_entries_on_status"
  end

  create_table "monthly_bills", force: :cascade do |t|
    t.string "account"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.decimal "default_amount", precision: 12, scale: 2
    t.integer "due_day", default: 1, null: false
    t.integer "kind", default: 0, null: false
    t.string "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_monthly_bills_on_active"
    t.index ["kind"], name: "index_monthly_bills_on_kind"
  end

  create_table "pay_schedules", force: :cascade do |t|
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
    t.integer "weekend_adjustment", default: 1, null: false
    t.index ["active"], name: "index_pay_schedules_on_active"
    t.index ["cadence"], name: "index_pay_schedules_on_cadence"
  end

  create_table "payment_plans", force: :cascade do |t|
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
    t.index ["active"], name: "index_payment_plans_on_active"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.string "account"
    t.boolean "active", default: true, null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.integer "due_day", default: 1, null: false
    t.string "name", null: false
    t.text "notes"
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_subscriptions_on_active"
  end

  add_foreign_key "expense_entries", "budget_months"
end
