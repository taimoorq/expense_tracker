class NormalizeLegacyBudgetMonthDates < ActiveRecord::Migration[8.1]
  def up
    collision_count = select_value(<<~SQL).to_i
      SELECT COUNT(*)
      FROM (
        SELECT user_id, DATE_TRUNC('month', month_on)::date AS normalized_month_on
        FROM budget_months
        GROUP BY user_id, normalized_month_on
        HAVING COUNT(*) > 1
      ) normalization_collisions
    SQL

    if collision_count.positive?
      raise ActiveRecord::MigrationError,
        "Cannot normalize budget month dates: #{collision_count} user/month collision groups require review."
    end

    execute <<~SQL
      UPDATE budget_months
      SET month_on = DATE_TRUNC('month', month_on)::date
      WHERE EXTRACT(DAY FROM month_on) <> 1
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Original budget month dates cannot be reconstructed after normalization"
  end
end
