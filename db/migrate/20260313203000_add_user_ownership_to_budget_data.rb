class AddUserOwnershipToBudgetData < ActiveRecord::Migration[8.1]
  def change
    add_reference :budget_months, :user, null: false, foreign_key: true, type: :uuid
    add_reference :expense_entries, :user, null: false, foreign_key: true, type: :uuid
    add_reference :pay_schedules, :user, null: false, foreign_key: true, type: :uuid
    add_reference :subscriptions, :user, null: false, foreign_key: true, type: :uuid
    add_reference :monthly_bills, :user, null: false, foreign_key: true, type: :uuid
    add_reference :payment_plans, :user, null: false, foreign_key: true, type: :uuid
    add_reference :credit_cards, :user, null: false, foreign_key: true, type: :uuid

    remove_index :budget_months, :month_on
    add_index :budget_months, [ :user_id, :month_on ], unique: true
  end
end
