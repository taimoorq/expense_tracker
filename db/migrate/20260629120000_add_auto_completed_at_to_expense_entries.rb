class AddAutoCompletedAtToExpenseEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :expense_entries, :auto_completed_at, :datetime
    add_index :expense_entries, :auto_completed_at
  end
end
