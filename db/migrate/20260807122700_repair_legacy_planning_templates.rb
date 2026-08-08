class RepairLegacyPlanningTemplates < ActiveRecord::Migration[8.1]
  def up
    reject_ambiguous_monthly_bills!
    repair_empty_billing_months
    reject_ambiguous_payment_plans!
    repair_completed_payment_plans
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Original recurring-template values cannot be reconstructed after repair"
  end

  private

  def reject_ambiguous_monthly_bills!
    ambiguous_count = select_value(<<~SQL).to_i
      SELECT COUNT(*)
      FROM monthly_bills
      WHERE CARDINALITY(billing_months) > 0
        AND (
          NOT (billing_months <@ ARRAY[1,2,3,4,5,6,7,8,9,10,11,12]::integer[])
          OR CARDINALITY(billing_months) <> CASE billing_frequency
            WHEN 0 THEN 12
            WHEN 1 THEN 4
            WHEN 2 THEN 2
            WHEN 3 THEN 1
          END
        )
    SQL

    return if ambiguous_count.zero?

    raise ActiveRecord::MigrationError,
      "Cannot repair monthly-bill schedules: #{ambiguous_count} non-empty schedules require review."
  end

  def repair_empty_billing_months
    execute <<~SQL
      UPDATE monthly_bills
      SET billing_months = CASE billing_frequency
        WHEN 0 THEN ARRAY[1,2,3,4,5,6,7,8,9,10,11,12]::integer[]
        WHEN 1 THEN ARRAY[1,4,7,10]::integer[]
        WHEN 2 THEN ARRAY[1,7]::integer[]
        WHEN 3 THEN ARRAY[1]::integer[]
      END
      WHERE CARDINALITY(billing_months) = 0
    SQL
  end

  def reject_ambiguous_payment_plans!
    ambiguous_count = select_value(<<~SQL).to_i
      WITH paid_evidence AS (
        SELECT payment_plans.id,
          GREATEST(
            payment_plans.amount_paid,
            COALESCE(SUM(COALESCE(expense_entries.actual_amount, expense_entries.planned_amount, 0)), 0)
          ) AS evidenced_paid
        FROM payment_plans
        LEFT JOIN expense_entries
          ON expense_entries.source_template_type = 'PaymentPlan'
         AND expense_entries.source_template_id = payment_plans.id
         AND expense_entries.status = 1
        GROUP BY payment_plans.id
      )
      SELECT COUNT(*)
      FROM payment_plans
      INNER JOIN paid_evidence ON paid_evidence.id = payment_plans.id
      WHERE (payment_plans.total_due <= 0 OR payment_plans.amount_paid > payment_plans.total_due)
        AND paid_evidence.evidenced_paid <= 0
    SQL

    return if ambiguous_count.zero?

    raise ActiveRecord::MigrationError,
      "Cannot repair payment-plan totals: #{ambiguous_count} plans have no positive paid evidence."
  end

  def repair_completed_payment_plans
    execute <<~SQL
      WITH paid_evidence AS (
        SELECT payment_plans.id,
          GREATEST(
            payment_plans.amount_paid,
            COALESCE(SUM(COALESCE(expense_entries.actual_amount, expense_entries.planned_amount, 0)), 0)
          ) AS evidenced_paid
        FROM payment_plans
        LEFT JOIN expense_entries
          ON expense_entries.source_template_type = 'PaymentPlan'
         AND expense_entries.source_template_id = payment_plans.id
         AND expense_entries.status = 1
        GROUP BY payment_plans.id
      )
      UPDATE payment_plans
      SET total_due = paid_evidence.evidenced_paid,
        amount_paid = paid_evidence.evidenced_paid,
        active = FALSE
      FROM paid_evidence
      WHERE payment_plans.id = paid_evidence.id
        AND (payment_plans.total_due <= 0 OR payment_plans.amount_paid > payment_plans.total_due)
    SQL
  end
end
