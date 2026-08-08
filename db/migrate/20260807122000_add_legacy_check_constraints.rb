class AddLegacyCheckConstraints < ActiveRecord::Migration[8.1]
  CHECKS = {
    users: {
      users_access_state_valid: "access_state BETWEEN 0 AND 1",
      users_failed_attempts_nonnegative: "failed_attempts >= 0",
      users_landing_page_valid: "default_landing_page IN ('overview', 'months', 'planning_templates', 'accounts', 'settings')",
      users_month_view_valid: "preferred_month_view IN ('timeline', 'breakdown', 'calendar', 'entries')",
      users_financial_rhythm_valid: "financial_rhythm IN ('steady_income', 'variable_income', 'shared_household', 'debt_payoff')"
    },
    admin_users: {
      admin_users_failed_attempts_nonnegative: "failed_attempts >= 0"
    },
    accounts: {
      accounts_kind_valid: "kind BETWEEN 0 AND 8",
      accounts_lock_version_nonnegative: "lock_version >= 0"
    },
    account_snapshots: {
      account_snapshots_lock_version_nonnegative: "lock_version >= 0"
    },
    budget_months: {
      budget_months_first_day: "EXTRACT(DAY FROM month_on) = 1",
      budget_months_lock_version_nonnegative: "lock_version >= 0"
    },
    expense_entries: {
      expense_entries_planned_amount_nonnegative: "planned_amount IS NULL OR planned_amount >= 0",
      expense_entries_actual_amount_nonnegative: "actual_amount IS NULL OR actual_amount >= 0",
      expense_entries_section_valid: "section BETWEEN 0 AND 6",
      expense_entries_status_valid: "status BETWEEN 0 AND 2",
      expense_entries_accounts_distinct: "source_account_id IS NULL OR destination_account_id IS NULL OR source_account_id <> destination_account_id",
      expense_entries_lock_version_nonnegative: "lock_version >= 0"
    },
    account_activity_imports: {
      activity_imports_header_row_positive: "header_row_number >= 1",
      activity_imports_counts_nonnegative: "rows_count >= 0 AND imported_count >= 0 AND duplicate_count >= 0",
      activity_imports_counts_coherent: "imported_count + duplicate_count <= rows_count",
      activity_imports_date_window_valid: "started_on IS NULL OR ended_on IS NULL OR ended_on >= started_on",
      activity_imports_amount_strategy_valid: "amount_strategy IN ('charges_are_negative', 'charges_are_positive', 'type_column')",
      activity_imports_file_digest_valid: "file_digest IS NULL OR file_digest ~ '^[0-9a-f]{64}$'",
      activity_imports_commit_key_valid: "commit_idempotency_key IS NULL OR commit_idempotency_key ~ '^[0-9a-f]{64}$'",
      activity_imports_lock_version_nonnegative: "lock_version >= 0"
    },
    account_activities: {
      account_activities_amount_nonnegative: "amount >= 0",
      account_activities_row_number_positive: "row_number >= 1"
    },
    pay_schedules: {
      pay_schedules_amount_positive: "amount > 0",
      pay_schedules_cadence_valid: "cadence BETWEEN 0 AND 3",
      pay_schedules_weekend_adjustment_valid: "weekend_adjustment BETWEEN 0 AND 2",
      pay_schedules_first_day_valid: "day_of_month_one IS NULL OR day_of_month_one BETWEEN 1 AND 31",
      pay_schedules_second_day_valid: "day_of_month_two IS NULL OR day_of_month_two BETWEEN 1 AND 31",
      pay_schedules_date_window_valid: "ends_on IS NULL OR ends_on >= first_pay_on",
      pay_schedules_lock_version_nonnegative: "lock_version >= 0"
    },
    subscriptions: {
      subscriptions_amount_positive: "amount > 0",
      subscriptions_due_day_valid: "due_day BETWEEN 1 AND 31",
      subscriptions_lock_version_nonnegative: "lock_version >= 0"
    },
    monthly_bills: {
      monthly_bills_amount_nonnegative: "default_amount IS NULL OR default_amount >= 0",
      monthly_bills_due_day_valid: "due_day BETWEEN 1 AND 31",
      monthly_bills_kind_valid: "kind BETWEEN 0 AND 1",
      monthly_bills_frequency_valid: "billing_frequency BETWEEN 0 AND 3",
      monthly_bills_months_valid: "billing_months <@ ARRAY[1,2,3,4,5,6,7,8,9,10,11,12]::integer[]",
      monthly_bills_month_count_valid: <<~SQL.squish,
        CARDINALITY(billing_months) = CASE billing_frequency
          WHEN 0 THEN 12
          WHEN 1 THEN 4
          WHEN 2 THEN 2
          WHEN 3 THEN 1
        END
      SQL
      monthly_bills_lock_version_nonnegative: "lock_version >= 0"
    },
    payment_plans: {
      payment_plans_total_positive: "total_due > 0",
      payment_plans_paid_nonnegative: "amount_paid >= 0",
      payment_plans_paid_within_total: "amount_paid <= total_due",
      payment_plans_target_nonnegative: "monthly_target IS NULL OR monthly_target >= 0",
      payment_plans_due_day_valid: "due_day BETWEEN 1 AND 31",
      payment_plans_lock_version_nonnegative: "lock_version >= 0"
    },
    credit_cards: {
      credit_cards_minimum_nonnegative: "minimum_payment >= 0",
      credit_cards_due_day_valid: "due_day BETWEEN 1 AND 31",
      credit_cards_priority_positive: "priority >= 1",
      credit_cards_lock_version_nonnegative: "lock_version >= 0"
    }
  }.freeze

  def change
    CHECKS.each do |table_name, constraints|
      constraints.each do |name, expression|
        add_check_constraint table_name,
          expression,
          name: name,
          validate: false,
          if_not_exists: true
      end
    end
  end
end
