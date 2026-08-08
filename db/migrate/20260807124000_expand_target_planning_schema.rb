class ExpandTargetPlanningSchema < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  LEGACY_WORKSPACE_TABLES = %i[
    accounts
    account_activities
    account_activity_imports
    budget_months
    expense_entries
    pay_schedules
    subscriptions
    monthly_bills
    payment_plans
    credit_cards
  ].freeze

  def up
    create_workspace_tables
    add_workspace_bridge_columns
    create_planning_tables
    add_planning_ownership_constraints
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Target-schema expansion is rolled back with a forward contract migration"
  end

  private

  def create_workspace_tables
    create_table :budget_workspaces, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.string :default_currency_code, null: false, default: "USD", limit: 3
      t.string :status, null: false, default: "active"
      t.datetime :closed_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.check_constraint "default_currency_code ~ '^[A-Z]{3}$'", name: "workspaces_currency_valid"
      t.check_constraint "status IN ('active', 'suspended', 'closing', 'closed')", name: "workspaces_status_valid"
      t.check_constraint "lock_version >= 0", name: "workspaces_lock_version_nonnegative"
      t.check_constraint "status = 'closed' OR closed_at IS NULL", name: "workspaces_closed_at_coherent"
    end

    create_table :workspace_memberships, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :role, null: false, default: "owner"
      t.string :status, null: false, default: "active"
      t.datetime :joined_at
      t.datetime :removed_at
      t.timestamps

      t.index %i[budget_workspace_id user_id], unique: true, name: "uidx_memberships_workspace_user"
      t.index %i[id budget_workspace_id], unique: true, name: "uidx_memberships_id_workspace"
      t.check_constraint "role IN ('owner', 'editor', 'viewer')", name: "memberships_role_valid"
      t.check_constraint "status IN ('invited', 'active', 'suspended', 'removed')", name: "memberships_status_valid"
      t.check_constraint "status = 'removed' OR removed_at IS NULL", name: "memberships_removed_at_coherent"
    end
  end

  def add_workspace_bridge_columns
    LEGACY_WORKSPACE_TABLES.each do |table_name|
      add_column table_name, :budget_workspace_id, :uuid, if_not_exists: true
      add_index table_name,
        :budget_workspace_id,
        algorithm: :concurrently,
        if_not_exists: true,
        name: "index_#{table_name}_on_budget_workspace_id"
      add_foreign_key table_name,
        :budget_workspaces,
        column: :budget_workspace_id,
        validate: false,
        if_not_exists: true
    end

    add_column :accounts, :currency_code, :string, limit: 3, if_not_exists: true
    add_column :accounts, :archived_at, :datetime, if_not_exists: true
    add_column :accounts, :closed_at, :datetime, if_not_exists: true
    add_index :accounts,
      %i[id budget_workspace_id],
      unique: true,
      algorithm: :concurrently,
      if_not_exists: true,
      name: "uidx_accounts_id_workspace"
  end

  def create_planning_tables
    create_categories
    create_budget_periods
    create_planning_templates
    create_recurrence_details
    create_recurring_occurrences
    create_budget_items
    create_month_closes
  end

  def create_categories
    create_table :categories, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.string :flow_kind, null: false
      t.string :budget_group, null: false
      t.integer :display_order, null: false, default: 0
      t.string :color_token
      t.datetime :archived_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index %i[id budget_workspace_id], unique: true, name: "uidx_categories_id_workspace"
      t.index %i[budget_workspace_id flow_kind display_order], name: "index_categories_on_workspace_flow_order"
      t.index "budget_workspace_id, lower(name)",
        unique: true,
        where: "archived_at IS NULL",
        name: "uidx_active_categories_workspace_name"
      t.check_constraint "flow_kind IN ('income', 'outflow', 'transfer')", name: "categories_flow_kind_valid"
      t.check_constraint "budget_group IN ('fixed', 'variable', 'debt', 'savings', 'other')", name: "categories_budget_group_valid"
      t.check_constraint "display_order >= 0", name: "categories_display_order_nonnegative"
      t.check_constraint "lock_version >= 0", name: "categories_lock_version_nonnegative"
    end
  end

  def create_budget_periods
    create_table :budget_periods, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.date :starts_on, null: false
      t.string :currency_code, null: false, limit: 3
      t.string :state, null: false, default: "open"
      t.text :notes
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index %i[budget_workspace_id starts_on], unique: true, name: "uidx_periods_workspace_start"
      t.index %i[id budget_workspace_id], unique: true, name: "uidx_periods_id_workspace"
      t.check_constraint "EXTRACT(DAY FROM starts_on) = 1", name: "periods_first_day"
      t.check_constraint "currency_code ~ '^[A-Z]{3}$'", name: "periods_currency_valid"
      t.check_constraint "state IN ('open', 'closing', 'closed', 'reopened')", name: "periods_state_valid"
      t.check_constraint "lock_version >= 0", name: "periods_lock_version_nonnegative"
    end
  end

  def create_planning_templates
    create_table :planning_templates, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :name, null: false
      t.string :flow_kind, null: false
      t.string :budget_group, null: false
      t.decimal :default_amount, precision: 19, scale: 4, null: false, default: 0
      t.string :currency_code, null: false, limit: 3
      t.references :category, type: :uuid
      t.uuid :source_account_id
      t.uuid :destination_account_id
      t.date :active_from
      t.date :active_until
      t.datetime :archived_at
      t.text :notes
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index %i[id budget_workspace_id], unique: true, name: "uidx_templates_id_workspace"
      t.index %i[budget_workspace_id kind archived_at], name: "index_templates_on_workspace_kind_archive"
      t.index "budget_workspace_id, lower(name)",
        unique: true,
        where: "archived_at IS NULL",
        name: "uidx_active_templates_workspace_name"
      t.index :source_account_id
      t.index :destination_account_id
      t.check_constraint "kind IN ('paycheck', 'subscription', 'bill', 'payment_plan', 'credit_card_payment')", name: "templates_kind_valid"
      t.check_constraint "flow_kind IN ('income', 'outflow', 'transfer')", name: "templates_flow_kind_valid"
      t.check_constraint "budget_group IN ('fixed', 'variable', 'debt', 'savings', 'other')", name: "templates_budget_group_valid"
      t.check_constraint "default_amount >= 0", name: "templates_amount_nonnegative"
      t.check_constraint "currency_code ~ '^[A-Z]{3}$'", name: "templates_currency_valid"
      t.check_constraint "source_account_id IS NULL OR destination_account_id IS NULL OR source_account_id <> destination_account_id", name: "templates_accounts_distinct"
      t.check_constraint "active_from IS NULL OR active_until IS NULL OR active_until >= active_from", name: "templates_active_window_valid"
      t.check_constraint "lock_version >= 0", name: "templates_lock_version_nonnegative"
    end
  end

  def create_recurrence_details
    create_table :recurrence_rules, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :planning_template, type: :uuid, null: false, foreign_key: true, index: { unique: true }
      t.string :cadence, null: false
      t.integer :interval_count, null: false, default: 1
      t.date :anchor_on, null: false
      t.integer :day_one
      t.integer :day_two
      t.string :weekend_policy, null: false, default: "none"
      t.date :starts_on, null: false
      t.date :ends_on
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.check_constraint "cadence IN ('weekly', 'monthly', 'yearly', 'custom_months')", name: "recurrence_rules_cadence_valid"
      t.check_constraint "interval_count > 0", name: "recurrence_rules_interval_positive"
      t.check_constraint "day_one IS NULL OR day_one BETWEEN 1 AND 31", name: "recurrence_rules_day_one_valid"
      t.check_constraint "day_two IS NULL OR day_two BETWEEN 1 AND 31", name: "recurrence_rules_day_two_valid"
      t.check_constraint "weekend_policy IN ('none', 'previous_friday', 'next_monday')", name: "recurrence_rules_weekend_valid"
      t.check_constraint "ends_on IS NULL OR ends_on >= starts_on", name: "recurrence_rules_window_valid"
      t.check_constraint "lock_version >= 0", name: "recurrence_rules_lock_version_nonnegative"
    end

    create_table :recurrence_months, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :recurrence_rule, type: :uuid, null: false, foreign_key: true
      t.integer :month_number, null: false
      t.timestamps

      t.index %i[recurrence_rule_id month_number], unique: true, name: "uidx_recurrence_months_rule_month"
      t.check_constraint "month_number BETWEEN 1 AND 12", name: "recurrence_months_number_valid"
    end

    create_table :payment_plan_terms, id: false do |t|
      t.references :planning_template, type: :uuid, null: false, primary_key: true, foreign_key: true
      t.decimal :total_due, precision: 19, scale: 4, null: false
      t.decimal :opening_paid_adjustment, precision: 19, scale: 4, null: false, default: 0
      t.decimal :monthly_target, precision: 19, scale: 4, null: false, default: 0
      t.date :target_completion_on
      t.timestamps

      t.check_constraint "total_due > 0", name: "payment_plan_terms_total_positive"
      t.check_constraint "opening_paid_adjustment >= 0 AND opening_paid_adjustment <= total_due", name: "payment_plan_terms_opening_valid"
      t.check_constraint "monthly_target >= 0", name: "payment_plan_terms_target_nonnegative"
    end

    create_table :credit_card_payment_policies, id: false do |t|
      t.references :planning_template, type: :uuid, null: false, primary_key: true, foreign_key: true
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.uuid :liability_account_id, null: false
      t.uuid :payment_account_id, null: false
      t.decimal :minimum_payment, precision: 19, scale: 4, null: false, default: 0
      t.integer :due_day, null: false
      t.integer :priority, null: false, default: 1
      t.string :estimate_policy, null: false, default: "minimum"
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index :liability_account_id
      t.index :payment_account_id
      t.check_constraint "liability_account_id <> payment_account_id", name: "card_policies_accounts_distinct"
      t.check_constraint "minimum_payment >= 0", name: "card_policies_minimum_nonnegative"
      t.check_constraint "due_day BETWEEN 1 AND 31", name: "card_policies_due_day_valid"
      t.check_constraint "priority > 0", name: "card_policies_priority_positive"
      t.check_constraint "estimate_policy IN ('minimum', 'statement_balance', 'available_cash', 'fixed_amount')", name: "card_policies_estimate_valid"
      t.check_constraint "lock_version >= 0", name: "card_policies_lock_version_nonnegative"
    end
  end

  def create_recurring_occurrences
    create_table :recurring_occurrences, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :planning_template, type: :uuid, null: false
      t.references :budget_period, type: :uuid, null: false
      t.date :scheduled_on, null: false
      t.string :slot_key, null: false, default: "default"
      t.string :state, null: false, default: "pending"
      t.timestamps

      t.index %i[id budget_workspace_id], unique: true, name: "uidx_occurrences_id_workspace"
      t.index %i[planning_template_id budget_period_id scheduled_on slot_key],
        unique: true,
        name: "uidx_occurrences_template_period_date_slot"
      t.check_constraint "state IN ('pending', 'materialized', 'skipped', 'cancelled', 'failed')", name: "occurrences_state_valid"
    end
  end

  def create_budget_items
    create_table :budget_items, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :budget_period, type: :uuid, null: false
      t.references :category, type: :uuid
      t.references :recurring_occurrence, type: :uuid
      t.date :scheduled_on
      t.string :flow_kind, null: false
      t.string :budget_group, null: false
      t.decimal :planned_amount, precision: 19, scale: 4, null: false, default: 0
      t.string :currency_code, null: false, limit: 3
      t.string :state, null: false, default: "open"
      t.string :name_snapshot
      t.string :payee_snapshot
      t.string :category_snapshot
      t.uuid :intended_source_account_id
      t.uuid :intended_destination_account_id
      t.string :priority_classification
      t.string :origin_kind, null: false, default: "manual"
      t.text :notes
      t.datetime :voided_at
      t.string :void_reason
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index %i[id budget_workspace_id], unique: true, name: "uidx_budget_items_id_workspace"
      t.index %i[budget_period_id state scheduled_on], name: "index_budget_items_on_period_state_schedule"
      t.index %i[budget_workspace_id state scheduled_on], name: "index_budget_items_on_workspace_state_schedule"
      t.index :intended_source_account_id
      t.index :intended_destination_account_id
      t.check_constraint "flow_kind IN ('income', 'outflow', 'transfer')", name: "budget_items_flow_kind_valid"
      t.check_constraint "budget_group IN ('fixed', 'variable', 'debt', 'savings', 'other')", name: "budget_items_budget_group_valid"
      t.check_constraint "planned_amount >= 0", name: "budget_items_amount_nonnegative"
      t.check_constraint "currency_code ~ '^[A-Z]{3}$'", name: "budget_items_currency_valid"
      t.check_constraint "state IN ('open', 'skipped', 'cancelled', 'voided')", name: "budget_items_state_valid"
      t.check_constraint "origin_kind IN ('manual', 'recurring', 'clone', 'budget_import', 'migration')", name: "budget_items_origin_valid"
      t.check_constraint "intended_source_account_id IS NULL OR intended_destination_account_id IS NULL OR intended_source_account_id <> intended_destination_account_id", name: "budget_items_accounts_distinct"
      t.check_constraint "state = 'voided' OR (voided_at IS NULL AND void_reason IS NULL)", name: "budget_items_void_coherent"
      t.check_constraint "lock_version >= 0", name: "budget_items_lock_version_nonnegative"
    end

    add_column :recurring_occurrences, :budget_item_id, :uuid
    add_index :recurring_occurrences, :budget_item_id, unique: true
  end

  def create_month_closes
    create_table :month_closes, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :budget_workspace, type: :uuid, null: false, foreign_key: true
      t.references :budget_period, type: :uuid, null: false
      t.references :closed_by_membership, type: :uuid
      t.references :reopens_month_close, type: :uuid
      t.string :state, null: false, default: "closed"
      t.string :calculation_version, null: false
      t.decimal :planned_income, precision: 19, scale: 4, null: false, default: 0
      t.decimal :planned_outflow, precision: 19, scale: 4, null: false, default: 0
      t.decimal :planned_net, precision: 19, scale: 4, null: false, default: 0
      t.decimal :actual_income, precision: 19, scale: 4, null: false, default: 0
      t.decimal :actual_outflow, precision: 19, scale: 4, null: false, default: 0
      t.decimal :actual_net, precision: 19, scale: 4, null: false, default: 0
      t.decimal :forecast_net, precision: 19, scale: 4, null: false, default: 0
      t.integer :unresolved_count, null: false, default: 0
      t.integer :unmatched_count, null: false, default: 0
      t.string :calculation_input_digest, null: false
      t.datetime :closed_at, null: false
      t.timestamps

      t.index %i[id budget_workspace_id], unique: true, name: "uidx_month_closes_id_workspace"
      t.index :budget_period_id, unique: true, where: "state = 'closed'", name: "uidx_active_month_close"
      t.check_constraint "state IN ('closed', 'superseded')", name: "month_closes_state_valid"
      t.check_constraint "unresolved_count >= 0 AND unmatched_count >= 0", name: "month_closes_counts_nonnegative"
      t.check_constraint "calculation_input_digest ~ '^[0-9a-f]{64}$'", name: "month_closes_digest_valid"
    end
  end

  def add_planning_ownership_constraints
    add_composite_foreign_key :planning_templates, :categories, :category_id
    add_composite_foreign_key :planning_templates, :accounts, :source_account_id
    add_composite_foreign_key :planning_templates, :accounts, :destination_account_id
    add_composite_foreign_key :recurring_occurrences, :planning_templates, :planning_template_id
    add_composite_foreign_key :recurring_occurrences, :budget_periods, :budget_period_id
    add_composite_foreign_key :budget_items, :budget_periods, :budget_period_id
    add_composite_foreign_key :budget_items, :categories, :category_id
    add_composite_foreign_key :budget_items, :recurring_occurrences, :recurring_occurrence_id
    add_composite_foreign_key :budget_items, :accounts, :intended_source_account_id
    add_composite_foreign_key :budget_items, :accounts, :intended_destination_account_id
    add_composite_foreign_key :recurring_occurrences, :budget_items, :budget_item_id
    add_composite_foreign_key :month_closes, :budget_periods, :budget_period_id

    add_composite_foreign_key :credit_card_payment_policies, :planning_templates, :planning_template_id
    add_composite_foreign_key :credit_card_payment_policies, :accounts, :liability_account_id
    add_composite_foreign_key :credit_card_payment_policies, :accounts, :payment_account_id
    add_composite_foreign_key :month_closes, :workspace_memberships, :closed_by_membership_id
    add_composite_foreign_key :month_closes, :month_closes, :reopens_month_close_id
  end

  def add_composite_foreign_key(from_table, to_table, foreign_id)
    add_foreign_key from_table,
      to_table,
      column: [ foreign_id, :budget_workspace_id ],
      primary_key: %i[id budget_workspace_id]
  end
end
