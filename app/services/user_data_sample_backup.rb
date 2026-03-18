class UserDataSampleBackup
  def filename
    "expense-tracker-sample-backup.json"
  end

  def as_json
    {
      format: UserDataExport::FORMAT_NAME,
      version: UserDataExport::FORMAT_VERSION,
      sample_backup: true,
      sample_notice: "Reference-only sample backup. Review the structure, but do not import this file unless you want example data added to your account.",
      exported_at: Time.current.iso8601,
      scopes: UserDataExport::SCOPES,
      data: {
        planning_templates: {
          pay_schedules: [
            {
              name: "Example Payroll",
              cadence: "biweekly",
              amount: "2450.00",
              first_pay_on: "2026-01-09",
              day_of_month_one: 9,
              day_of_month_two: 23,
              weekend_adjustment: "previous_friday",
              account: "Checking",
              active: true
            }
          ],
          subscriptions: [
            {
              name: "Example Streaming",
              amount: "18.99",
              due_day: 12,
              account: "Credit Card",
              notes: "Sample recurring subscription",
              active: true
            }
          ],
          monthly_bills: [
            {
              name: "Example Electric",
              kind: "variable_bill",
              default_amount: "120.00",
              due_day: 18,
              account: "Checking",
              notes: "Sample utility bill",
              active: true
            }
          ],
          payment_plans: [
            {
              name: "Example Tax Plan",
              total_due: "2400.00",
              amount_paid: "600.00",
              monthly_target: "200.00",
              due_day: 20,
              account: "Checking",
              notes: "Sample installment plan",
              active: true
            }
          ],
          credit_cards: [
            {
              name: "Example Visa",
              minimum_payment: "75.00",
              due_day: 24,
              priority: 1,
              account: "Credit Card",
              notes: "Sample credit card minimum payment",
              active: true
            }
          ]
        },
        budget_months: [
          {
            label: "March 2026",
            month_on: "2026-03-01",
            leftover: "340.00",
            notes: "Example month for backup structure reference",
            expense_entries: [
              {
                occurred_on: "2026-03-09",
                section: "income",
                category: "Paycheck",
                payee: "Example Payroll",
                planned_amount: "2450.00",
                actual_amount: "2450.00",
                account: "Checking",
                source_account: "Checking",
                status: "paid",
                need_or_want: nil,
                notes: "Generated from sample pay schedule",
                source_file: "pay_schedule",
                source_template_type: "PaySchedule",
                source_template_name: "Example Payroll"
              },
              {
                occurred_on: "2026-03-18",
                section: "fixed",
                category: "Utilities",
                payee: "Example Electric",
                planned_amount: "120.00",
                actual_amount: nil,
                account: "Checking",
                source_account: "Checking",
                status: "planned",
                need_or_want: "Need",
                notes: "Sample month entry",
                source_file: "monthly_bill",
                source_template_type: "MonthlyBill",
                source_template_name: "Example Electric"
              }
            ]
          }
        ],
        accounts: [
          {
            name: "Example Checking",
            institution_name: "Sample Bank",
            kind: "checking",
            active: true,
            include_in_net_worth: true,
            include_in_cash: true,
            notes: "Primary spending account",
            account_snapshots: [
              {
                recorded_on: "2026-03-15",
                balance: "2380.00",
                available_balance: "2325.00",
                notes: "Mid-month sample snapshot"
              }
            ]
          }
        ]
      }
    }
  end

  def to_json(*_args)
    JSON.pretty_generate(as_json)
  end
end
