class AddSourceAccountToExpenseEntries < ActiveRecord::Migration[8.1]
  def up
    add_reference :expense_entries, :source_account, type: :uuid, foreign_key: { to_table: :accounts }, index: true

    execute <<~SQL.squish
      UPDATE expense_entries AS entry
      SET source_account_id = account.id
      FROM accounts AS account
      WHERE entry.source_account_id IS NULL
        AND entry.user_id = account.user_id
        AND entry.account = account.name
    SQL
  end

  def down
    remove_reference :expense_entries, :source_account, foreign_key: { to_table: :accounts }, index: true
  end
end
