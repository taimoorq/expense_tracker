class AddTransactionTiming < ActiveRecord::Migration[8.1]
  def change
    add_column :budget_workspaces, :time_zone, :string, null: false, default: "UTC"
    add_column :budget_workspaces, :bank_sync_epoch, :integer, null: false, default: 0
    { expense_entries: :occurred_at, budget_items: :scheduled_at, financial_transactions: :transacted_at,
      account_activities: :transacted_at, month_close_item_snapshots: :scheduled_at,
      month_close_transaction_snapshots: :transacted_at }.each do |table, column|
      add_column table, column, :datetime, precision: 6
      add_column table, :timing_time_zone, :string
    end
    add_column :financial_transactions, :posted_at, :datetime, precision: 6
    add_column :account_activities, :posted_at, :datetime, precision: 6
    add_index :financial_transactions, [ :budget_workspace_id, :transacted_at, :id ], name: "index_transactions_on_workspace_time"
  end
end
