class AddPageLoadIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  RECURRING_SOURCE_FILES = %w[pay_schedule subscription monthly_bill payment_plan].freeze

  def change
    add_index :accounts,
      [ :user_id, :active, :name ],
      order: { active: :desc, name: :asc },
      name: "index_accounts_on_user_active_name",
      algorithm: :concurrently,
      if_not_exists: true

    add_index :expense_entries,
      [ :budget_month_id, :occurred_on, :created_at ],
      name: "index_expense_entries_on_month_chronological",
      algorithm: :concurrently,
      if_not_exists: true

    add_index :expense_entries,
      [ :source_account_id, :occurred_on, :created_at ],
      order: { occurred_on: :desc, created_at: :desc },
      where: "source_account_id IS NOT NULL",
      name: "index_expense_entries_on_source_account_recent",
      algorithm: :concurrently,
      if_not_exists: true

    add_index :expense_entries,
      [ :user_id, :status, :occurred_on ],
      where: "occurred_on IS NOT NULL AND source_file IN (#{quoted_recurring_source_files})",
      name: "index_expense_entries_on_user_due_recurring",
      algorithm: :concurrently,
      if_not_exists: true

    add_index :pay_schedules,
      [ :user_id, :name ],
      name: "index_pay_schedules_on_user_name",
      algorithm: :concurrently,
      if_not_exists: true

    add_index :subscriptions,
      [ :user_id, :due_day, :name ],
      name: "index_subscriptions_on_user_due_day_name",
      algorithm: :concurrently,
      if_not_exists: true

    add_index :monthly_bills,
      [ :user_id, :kind, :due_day, :name ],
      name: "index_monthly_bills_on_user_kind_due_day_name",
      algorithm: :concurrently,
      if_not_exists: true

    add_index :payment_plans,
      [ :user_id, :due_day, :name ],
      name: "index_payment_plans_on_user_due_day_name",
      algorithm: :concurrently,
      if_not_exists: true

    add_index :credit_cards,
      [ :user_id, :priority, :name ],
      name: "index_credit_cards_on_user_priority_name",
      algorithm: :concurrently,
      if_not_exists: true
  end

  private

  def quoted_recurring_source_files
    RECURRING_SOURCE_FILES.map { |source_file| quote(source_file) }.join(", ")
  end
end
