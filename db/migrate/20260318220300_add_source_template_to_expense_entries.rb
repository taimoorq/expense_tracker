class AddSourceTemplateToExpenseEntries < ActiveRecord::Migration[8.1]
  def change
    add_reference :expense_entries, :source_template, polymorphic: true, type: :uuid
  end
end
