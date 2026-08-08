class ValidateLegacyConstraints < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  FOREIGN_KEYS = {
    expense_entries: %w[
      fk_entries_month_owner
      fk_entries_source_account_owner
      fk_entries_destination_account_owner
    ],
    account_activity_imports: %w[fk_activity_imports_account_owner],
    account_activities: %w[
      fk_activities_account_owner
      fk_activities_import_scope
      fk_activities_entry_owner
    ],
    pay_schedules: %w[fk_pay_schedules_account_owner],
    subscriptions: %w[fk_subscriptions_account_owner],
    monthly_bills: %w[fk_monthly_bills_account_owner],
    payment_plans: %w[fk_payment_plans_account_owner],
    credit_cards: %w[
      fk_credit_cards_linked_account_owner
      fk_credit_cards_payment_account_owner
    ]
  }.freeze

  CHECK_CONSTRAINTS = {
    users: %w[
      users_access_state_valid
      users_failed_attempts_nonnegative
      users_landing_page_valid
      users_month_view_valid
      users_financial_rhythm_valid
    ],
    admin_users: %w[admin_users_failed_attempts_nonnegative],
    accounts: %w[accounts_kind_valid accounts_lock_version_nonnegative],
    account_snapshots: %w[account_snapshots_lock_version_nonnegative],
    budget_months: %w[budget_months_first_day budget_months_lock_version_nonnegative],
    expense_entries: %w[
      expense_entries_planned_amount_nonnegative
      expense_entries_actual_amount_nonnegative
      expense_entries_section_valid
      expense_entries_status_valid
      expense_entries_accounts_distinct
      expense_entries_lock_version_nonnegative
    ],
    account_activity_imports: %w[
      activity_imports_header_row_positive
      activity_imports_counts_nonnegative
      activity_imports_counts_coherent
      activity_imports_date_window_valid
      activity_imports_amount_strategy_valid
      activity_imports_file_digest_valid
      activity_imports_commit_key_valid
      activity_imports_lock_version_nonnegative
    ],
    account_activities: %w[
      account_activities_amount_nonnegative
      account_activities_row_number_positive
    ],
    pay_schedules: %w[
      pay_schedules_amount_positive
      pay_schedules_cadence_valid
      pay_schedules_weekend_adjustment_valid
      pay_schedules_first_day_valid
      pay_schedules_second_day_valid
      pay_schedules_date_window_valid
      pay_schedules_lock_version_nonnegative
    ],
    subscriptions: %w[
      subscriptions_amount_positive
      subscriptions_due_day_valid
      subscriptions_lock_version_nonnegative
    ],
    monthly_bills: %w[
      monthly_bills_amount_nonnegative
      monthly_bills_due_day_valid
      monthly_bills_kind_valid
      monthly_bills_frequency_valid
      monthly_bills_months_valid
      monthly_bills_month_count_valid
      monthly_bills_lock_version_nonnegative
    ],
    payment_plans: %w[
      payment_plans_total_positive
      payment_plans_paid_nonnegative
      payment_plans_paid_within_total
      payment_plans_target_nonnegative
      payment_plans_due_day_valid
      payment_plans_lock_version_nonnegative
    ],
    credit_cards: %w[
      credit_cards_minimum_nonnegative
      credit_cards_due_day_valid
      credit_cards_priority_positive
      credit_cards_lock_version_nonnegative
    ]
  }.freeze

  def up
    FOREIGN_KEYS.each do |table_name, names|
      names.each { |name| validate_foreign_key table_name, name: name }
    end

    CHECK_CONSTRAINTS.each do |table_name, names|
      names.each { |name| validate_check_constraint table_name, name: name }
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "PostgreSQL constraints cannot be made NOT VALID after validation"
  end
end
