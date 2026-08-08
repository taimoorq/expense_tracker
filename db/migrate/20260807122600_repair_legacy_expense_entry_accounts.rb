class RepairLegacyExpenseEntryAccounts < ActiveRecord::Migration[8.1]
  def up
    ambiguous_count = select_value(<<~SQL).to_i
      SELECT COUNT(*)
      FROM expense_entries
      WHERE source_account_id IS NOT NULL
        AND source_account_id = destination_account_id
        AND section IS DISTINCT FROM 0
    SQL

    if ambiguous_count.positive?
      raise ActiveRecord::MigrationError,
        "Cannot repair expense entry accounts: #{ambiguous_count} non-income entries require review."
    end

    execute <<~SQL
      UPDATE expense_entries
      SET destination_account_id = NULL
      WHERE source_account_id IS NOT NULL
        AND source_account_id = destination_account_id
        AND section = 0
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Original duplicate destination accounts cannot be reconstructed after repair"
  end
end
