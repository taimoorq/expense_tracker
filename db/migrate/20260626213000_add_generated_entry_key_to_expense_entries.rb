class AddGeneratedEntryKeyToExpenseEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :expense_entries, :generated_entry_key, :string
    add_index :expense_entries,
      :generated_entry_key,
      unique: true,
      where: "generated_entry_key IS NOT NULL",
      name: "index_expense_entries_on_generated_entry_key_unique"
  end
end
