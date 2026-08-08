module Platform
  class LegacyDataQualityReport
    Rule = Data.define(:key, :description, :identifiers_sql)

    Finding = Data.define(:key, :description, :violation_count, :sample_identifiers) do
      def clean?
        violation_count.zero?
      end

      def as_json(*)
        {
          key: key,
          description: description,
          clean: clean?,
          violation_count: violation_count,
          sample_identifiers: sample_identifiers
        }
      end
    end

    Result = Data.define(:generated_at, :findings) do
      def clean?
        findings.all?(&:clean?)
      end

      def violation_count
        findings.sum(&:violation_count)
      end

      def as_json(*)
        {
          generated_at: generated_at.iso8601,
          clean: clean?,
          violation_count: violation_count,
          findings: findings.map(&:as_json)
        }
      end
    end

    DEFAULT_SAMPLE_LIMIT = 10
    VALID_BILLING_MONTHS_SQL = "ARRAY[1,2,3,4,5,6,7,8,9,10,11,12]::integer[]".freeze

    RULES = [
      Rule.new(
        key: :user_invalid_state_or_preference,
        description: "User access state and persisted navigation preferences must use supported values.",
        identifiers_sql: <<~SQL
          SELECT id::text AS identifier
          FROM users
          WHERE access_state NOT BETWEEN 0 AND 1
             OR failed_attempts < 0
             OR default_landing_page NOT IN ('overview', 'months', 'planning_templates', 'accounts', 'settings')
             OR preferred_month_view NOT IN ('timeline', 'breakdown', 'calendar', 'entries')
             OR financial_rhythm NOT IN ('steady_income', 'variable_income', 'shared_household', 'debt_payoff')
        SQL
      ),
      Rule.new(
        key: :admin_invalid_security_counter,
        description: "Administrator failed-attempt counters cannot be negative.",
        identifiers_sql: <<~SQL
          SELECT id::text AS identifier
          FROM admin_users
          WHERE failed_attempts < 0
        SQL
      ),
      Rule.new(
        key: :legacy_negative_lock_version,
        description: "Optimistically locked financial records cannot have a negative version.",
        identifiers_sql: <<~SQL
          SELECT identifier
          FROM (
            SELECT 'account:' || id::text AS identifier FROM accounts WHERE lock_version < 0
            UNION ALL
            SELECT 'account_snapshot:' || id::text FROM account_snapshots WHERE lock_version < 0
            UNION ALL
            SELECT 'activity_import:' || id::text FROM account_activity_imports WHERE lock_version < 0
            UNION ALL
            SELECT 'budget_month:' || id::text FROM budget_months WHERE lock_version < 0
            UNION ALL
            SELECT 'expense_entry:' || id::text FROM expense_entries WHERE lock_version < 0
            UNION ALL
            SELECT 'pay_schedule:' || id::text FROM pay_schedules WHERE lock_version < 0
            UNION ALL
            SELECT 'subscription:' || id::text FROM subscriptions WHERE lock_version < 0
            UNION ALL
            SELECT 'monthly_bill:' || id::text FROM monthly_bills WHERE lock_version < 0
            UNION ALL
            SELECT 'payment_plan:' || id::text FROM payment_plans WHERE lock_version < 0
            UNION ALL
            SELECT 'credit_card:' || id::text FROM credit_cards WHERE lock_version < 0
          ) invalid_versions
        SQL
      ),
      Rule.new(
        key: :budget_month_not_first_day,
        description: "Budget months must start on the first day of a calendar month.",
        identifiers_sql: <<~SQL
          SELECT id::text AS identifier
          FROM budget_months
          WHERE EXTRACT(DAY FROM month_on) <> 1
        SQL
      ),
      Rule.new(
        key: :expense_entry_month_owner_mismatch,
        description: "Expense entries and their budget months must have the same owner.",
        identifiers_sql: <<~SQL
          SELECT expense_entries.id::text AS identifier
          FROM expense_entries
          INNER JOIN budget_months ON budget_months.id = expense_entries.budget_month_id
          WHERE expense_entries.user_id <> budget_months.user_id
        SQL
      ),
      Rule.new(
        key: :expense_entry_outside_month,
        description: "Dated expense entries must fall inside their budget month unless a linked pay schedule legitimately adjusts a boundary weekend.",
        identifiers_sql: <<~SQL
          SELECT expense_entries.id::text AS identifier
          FROM expense_entries
          INNER JOIN budget_months ON budget_months.id = expense_entries.budget_month_id
          LEFT JOIN pay_schedules
            ON expense_entries.source_template_type = 'PaySchedule'
           AND expense_entries.source_template_id = pay_schedules.id
           AND expense_entries.source_file = 'pay_schedule'
          WHERE expense_entries.occurred_on IS NOT NULL
            AND DATE_TRUNC('month', expense_entries.occurred_on)::date <> budget_months.month_on
            AND NOT COALESCE((
              pay_schedules.weekend_adjustment = 2
              AND expense_entries.occurred_on = CASE
                WHEN EXTRACT(ISODOW FROM budget_months.month_on + INTERVAL '1 month - 1 day') = 6
                  THEN (budget_months.month_on + INTERVAL '1 month + 1 day')::date
                WHEN EXTRACT(ISODOW FROM budget_months.month_on + INTERVAL '1 month - 1 day') = 7
                  THEN (budget_months.month_on + INTERVAL '1 month')::date
              END
            ), FALSE)
            AND NOT COALESCE((
              pay_schedules.weekend_adjustment = 1
              AND expense_entries.occurred_on = CASE
                WHEN EXTRACT(ISODOW FROM budget_months.month_on) = 6
                  THEN (budget_months.month_on - INTERVAL '1 day')::date
                WHEN EXTRACT(ISODOW FROM budget_months.month_on) = 7
                  THEN (budget_months.month_on - INTERVAL '2 days')::date
              END
            ), FALSE)
        SQL
      ),
      Rule.new(
        key: :expense_entry_account_owner_mismatch,
        description: "Expense-entry source and destination accounts must share the entry owner.",
        identifiers_sql: <<~SQL
          SELECT expense_entries.id::text AS identifier
          FROM expense_entries
          LEFT JOIN accounts source_accounts ON source_accounts.id = expense_entries.source_account_id
          LEFT JOIN accounts destination_accounts ON destination_accounts.id = expense_entries.destination_account_id
          WHERE (source_accounts.id IS NOT NULL AND source_accounts.user_id <> expense_entries.user_id)
             OR (destination_accounts.id IS NOT NULL AND destination_accounts.user_id <> expense_entries.user_id)
        SQL
      ),
      Rule.new(
        key: :expense_entry_same_account,
        description: "An expense entry cannot use the same source and destination account.",
        identifiers_sql: <<~SQL
          SELECT id::text AS identifier
          FROM expense_entries
          WHERE source_account_id IS NOT NULL
            AND source_account_id = destination_account_id
        SQL
      ),
      Rule.new(
        key: :expense_entry_invalid_amount_or_enum,
        description: "Expense-entry amounts and enum values must be in their supported ranges.",
        identifiers_sql: <<~SQL
          SELECT id::text AS identifier
          FROM expense_entries
          WHERE planned_amount < 0
             OR actual_amount < 0
             OR section NOT BETWEEN 0 AND 6
             OR status NOT BETWEEN 0 AND 2
        SQL
      ),
      Rule.new(
        key: :account_invalid_kind,
        description: "Account kind values must be in the supported range.",
        identifiers_sql: <<~SQL
          SELECT id::text AS identifier
          FROM accounts
          WHERE kind NOT BETWEEN 0 AND 8
        SQL
      ),
      Rule.new(
        key: :account_import_owner_mismatch,
        description: "Account imports must belong to the same user as their account.",
        identifiers_sql: <<~SQL
          SELECT account_activity_imports.id::text AS identifier
          FROM account_activity_imports
          INNER JOIN accounts ON accounts.id = account_activity_imports.account_id
          WHERE account_activity_imports.user_id <> accounts.user_id
        SQL
      ),
      Rule.new(
        key: :account_activity_scope_mismatch,
        description: "Imported rows must share the user and account of their import batch.",
        identifiers_sql: <<~SQL
          SELECT account_activities.id::text AS identifier
          FROM account_activities
          INNER JOIN accounts ON accounts.id = account_activities.account_id
          INNER JOIN account_activity_imports ON account_activity_imports.id = account_activities.account_activity_import_id
          WHERE account_activities.user_id <> accounts.user_id
             OR account_activities.user_id <> account_activity_imports.user_id
             OR account_activities.account_id <> account_activity_imports.account_id
        SQL
      ),
      Rule.new(
        key: :account_activity_entry_owner_mismatch,
        description: "An imported row may only match an expense entry owned by the same user.",
        identifiers_sql: <<~SQL
          SELECT account_activities.id::text AS identifier
          FROM account_activities
          INNER JOIN expense_entries ON expense_entries.id = account_activities.expense_entry_id
          WHERE account_activities.user_id <> expense_entries.user_id
        SQL
      ),
      Rule.new(
        key: :account_activity_invalid_amount_or_row,
        description: "Imported activity amounts and row numbers must be coherent.",
        identifiers_sql: <<~SQL
          SELECT id::text AS identifier
          FROM account_activities
          WHERE amount < 0 OR row_number < 1
        SQL
      ),
      Rule.new(
        key: :account_import_invalid_counts_or_dates,
        description: "Import counts, header row, and coverage dates must be coherent.",
        identifiers_sql: <<~SQL
          SELECT id::text AS identifier
          FROM account_activity_imports
          WHERE header_row_number < 1
             OR rows_count < 0
             OR imported_count < 0
             OR duplicate_count < 0
             OR imported_count + duplicate_count > rows_count
             OR (started_on IS NOT NULL AND ended_on IS NOT NULL AND ended_on < started_on)
             OR amount_strategy NOT IN ('charges_are_negative', 'charges_are_positive', 'type_column')
             OR (file_digest IS NOT NULL AND file_digest !~ '^[0-9a-f]{64}$')
             OR (commit_idempotency_key IS NOT NULL AND commit_idempotency_key !~ '^[0-9a-f]{64}$')
        SQL
      ),
      Rule.new(
        key: :institution_balance_missing_as_of,
        description: "Institution balances in import metadata need an explicit as-of date.",
        identifiers_sql: <<~SQL
          SELECT id::text AS identifier
          FROM account_activity_imports
          WHERE COALESCE(metadata ->> 'institution_balance', '') <> ''
            AND COALESCE(metadata ->> 'institution_balance_as_of', '') = ''
        SQL
      ),
      Rule.new(
        key: :planning_template_account_owner_mismatch,
        description: "Recurring-template account links must stay within the template owner.",
        identifiers_sql: <<~SQL
          SELECT identifier
          FROM (
            SELECT 'pay_schedule:' || pay_schedules.id::text AS identifier
            FROM pay_schedules INNER JOIN accounts ON accounts.id = pay_schedules.linked_account_id
            WHERE pay_schedules.user_id <> accounts.user_id
            UNION ALL
            SELECT 'subscription:' || subscriptions.id::text
            FROM subscriptions INNER JOIN accounts ON accounts.id = subscriptions.linked_account_id
            WHERE subscriptions.user_id <> accounts.user_id
            UNION ALL
            SELECT 'monthly_bill:' || monthly_bills.id::text
            FROM monthly_bills INNER JOIN accounts ON accounts.id = monthly_bills.linked_account_id
            WHERE monthly_bills.user_id <> accounts.user_id
            UNION ALL
            SELECT 'payment_plan:' || payment_plans.id::text
            FROM payment_plans INNER JOIN accounts ON accounts.id = payment_plans.linked_account_id
            WHERE payment_plans.user_id <> accounts.user_id
            UNION ALL
            SELECT 'credit_card_linked:' || credit_cards.id::text
            FROM credit_cards INNER JOIN accounts ON accounts.id = credit_cards.linked_account_id
            WHERE credit_cards.user_id <> accounts.user_id
            UNION ALL
            SELECT 'credit_card_payment:' || credit_cards.id::text
            FROM credit_cards INNER JOIN accounts ON accounts.id = credit_cards.payment_account_id
            WHERE credit_cards.user_id <> accounts.user_id
          ) mismatches
        SQL
      ),
      Rule.new(
        key: :planning_template_invalid_amount_day_or_enum,
        description: "Recurring-template amounts, days, priorities, and enums must be supported.",
        identifiers_sql: <<~SQL
          SELECT identifier
          FROM (
            SELECT 'pay_schedule:' || id::text AS identifier
            FROM pay_schedules
            WHERE amount <= 0 OR cadence NOT BETWEEN 0 AND 3 OR weekend_adjustment NOT BETWEEN 0 AND 2
               OR (day_of_month_one IS NOT NULL AND day_of_month_one NOT BETWEEN 1 AND 31)
               OR (day_of_month_two IS NOT NULL AND day_of_month_two NOT BETWEEN 1 AND 31)
            UNION ALL
            SELECT 'subscription:' || id::text
            FROM subscriptions
            WHERE amount <= 0 OR due_day NOT BETWEEN 1 AND 31
            UNION ALL
            SELECT 'monthly_bill:' || id::text
            FROM monthly_bills
            WHERE default_amount < 0 OR due_day NOT BETWEEN 1 AND 31
               OR kind NOT BETWEEN 0 AND 1 OR billing_frequency NOT BETWEEN 0 AND 3
            UNION ALL
            SELECT 'payment_plan:' || id::text
            FROM payment_plans
            WHERE total_due <= 0 OR amount_paid < 0 OR monthly_target < 0
               OR due_day NOT BETWEEN 1 AND 31
            UNION ALL
            SELECT 'credit_card:' || id::text
            FROM credit_cards
            WHERE minimum_payment < 0 OR due_day NOT BETWEEN 1 AND 31 OR priority < 1
          ) invalid_templates
        SQL
      ),
      Rule.new(
        key: :monthly_bill_invalid_billing_months,
        description: "Monthly-bill schedules must contain valid months and the expected cadence count.",
        identifiers_sql: <<~SQL
          SELECT id::text AS identifier
          FROM monthly_bills
          WHERE NOT (billing_months <@ #{VALID_BILLING_MONTHS_SQL})
             OR CARDINALITY(billing_months) <> CASE billing_frequency
               WHEN 0 THEN 12
               WHEN 1 THEN 4
               WHEN 2 THEN 2
               WHEN 3 THEN 1
             END
        SQL
      ),
      Rule.new(
        key: :planning_template_invalid_date_window,
        description: "Recurring-template and import end dates cannot precede their start dates.",
        identifiers_sql: <<~SQL
          SELECT 'pay_schedule:' || id::text AS identifier
          FROM pay_schedules
          WHERE ends_on IS NOT NULL AND ends_on < first_pay_on
        SQL
      ),
      Rule.new(
        key: :payment_plan_progress_out_of_bounds,
        description: "Payment-plan opening progress cannot exceed its total due.",
        identifiers_sql: <<~SQL
          SELECT id::text AS identifier
          FROM payment_plans
          WHERE amount_paid > total_due
        SQL
      ),
      Rule.new(
        key: :generated_entry_missing_durable_key,
        description: "Template-linked generated entries need a durable generated identity.",
        identifiers_sql: <<~SQL
          SELECT id::text AS identifier
          FROM expense_entries
          WHERE source_template_id IS NOT NULL
            AND source_file IN ('pay_schedule', 'subscription', 'monthly_bill', 'payment_plan', 'credit_card_estimate')
            AND generated_entry_key IS NULL
        SQL
      ),
      Rule.new(
        key: :legacy_account_name_unresolved,
        description: "Legacy account labels without a foreign key should resolve to one owned account.",
        identifiers_sql: <<~SQL
          SELECT expense_entries.id::text AS identifier
          FROM expense_entries
          WHERE source_account_id IS NULL
            AND NULLIF(BTRIM(account), '') IS NOT NULL
            AND (
              SELECT COUNT(*)
              FROM accounts
              WHERE accounts.user_id = expense_entries.user_id
                AND LOWER(BTRIM(accounts.name)) = LOWER(BTRIM(expense_entries.account))
            ) <> 1
        SQL
      )
    ].freeze

    def self.call(sample_limit: DEFAULT_SAMPLE_LIMIT)
      new(sample_limit: sample_limit).call
    end

    def initialize(sample_limit: DEFAULT_SAMPLE_LIMIT, connection: ApplicationRecord.connection)
      @sample_limit = Integer(sample_limit)
      @connection = connection
      raise ArgumentError, "sample_limit must be positive" unless @sample_limit.positive?
    end

    def call
      Result.new(generated_at: Time.current, findings: RULES.map { |rule| evaluate(rule) })
    end

    private

    attr_reader :connection, :sample_limit

    def evaluate(rule)
      sql = rule.identifiers_sql.squish
      count = connection.raw_connection.exec("SELECT COUNT(*) FROM (#{sql}) violations").getvalue(0, 0).to_i
      identifiers = connection.raw_connection
        .exec("SELECT identifier FROM (#{sql}) violations ORDER BY identifier LIMIT #{sample_limit}")
        .column_values(0)

      Finding.new(
        key: rule.key,
        description: rule.description,
        violation_count: count,
        sample_identifiers: identifiers
      )
    end
  end
end
