class AddDestinationAccountToExpenseEntries < ActiveRecord::Migration[8.1]
  def change
    add_reference :expense_entries, :destination_account, type: :uuid, foreign_key: { to_table: :accounts }, index: true
    add_index :expense_entries,
      [ :destination_account_id, :occurred_on, :created_at ],
      name: "index_expense_entries_on_destination_account_recent",
      order: { occurred_on: :desc, created_at: :desc },
      where: "destination_account_id IS NOT NULL"

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE expense_entries
          SET destination_account_id = credit_cards.linked_account_id
          FROM credit_cards
          WHERE expense_entries.source_template_type = 'CreditCard'
            AND expense_entries.source_template_id = credit_cards.id
            AND expense_entries.destination_account_id IS NULL
            AND credit_cards.linked_account_id IS NOT NULL
        SQL
      end
    end
  end
end
