module Platform
  class UserDataSampleBackup
    def filename
      "expense-tracker-sample-backup.json"
    end

    def as_json
      {
        format: Platform::UserDataExport::FORMAT_NAME,
        version: Platform::UserDataExport::FORMAT_VERSION,
        sample_backup: true,
        sample_notice: "Reference-only sample backup. Review the structure, but do not import this file unless you want example data added to your account.",
        exported_at: Time.current.iso8601,
        scopes: Platform::UserDataExport::SCOPES,
        data: {
          preferences: {
            default_landing_page: "overview",
            preferred_month_view: "entries",
            financial_rhythm: "debt_payoff"
          },
          planning_templates: {
            pay_schedules: [
              {
                name: "Example Payroll",
                cadence: "biweekly",
                amount: "2450.00",
                first_pay_on: "2026-01-09",
                ends_on: nil,
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
                billing_frequency: "monthly",
                billing_months: (1..12).to_a,
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
                linked_account: "Example Visa",
                payment_account: "Example Checking",
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
                  auto_completed_at: "2026-03-09T09:00:00Z",
                  need_or_want: nil,
                  notes: "Generated from sample pay schedule",
                  source_file: "pay_schedule",
                  source_template_type: "PaySchedule",
                  source_template_name: "Example Payroll",
                  generated_entry_key: "recurring:v1:PaySchedule:sample-payroll:2026-03-01:2026-03-09",
                  created_at: "2026-03-01T12:00:00Z",
                  updated_at: "2026-03-09T09:00:00Z"
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
                  auto_completed_at: nil,
                  need_or_want: "Need",
                  notes: "Sample month entry",
                  source_file: "monthly_bill",
                  source_template_type: "MonthlyBill",
                  source_template_name: "Example Electric",
                  generated_entry_key: "recurring:v1:MonthlyBill:sample-electric:2026-03-01:2026-03-18",
                  created_at: "2026-03-01T12:05:00Z",
                  updated_at: "2026-03-01T12:05:00Z"
                },
                {
                  occurred_on: "2026-03-24",
                  section: "debt",
                  category: "Credit Card",
                  payee: "Example Visa",
                  planned_amount: "120.00",
                  actual_amount: nil,
                  account: "Example Checking",
                  source_account: "Example Checking",
                  destination_account: "Example Visa",
                  status: "planned",
                  auto_completed_at: nil,
                  need_or_want: "Need",
                  notes: "Manual extra payment linked to the recurring card",
                  source_file: "manual",
                  source_template_type: "CreditCard",
                  source_template_name: "Example Visa",
                  generated_entry_key: nil,
                  created_at: "2026-03-01T12:10:00Z",
                  updated_at: "2026-03-01T12:10:00Z"
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
            },
            {
              name: "Example Visa",
              institution_name: "Sample Bank",
              kind: "credit_card",
              active: true,
              include_in_net_worth: true,
              include_in_cash: false,
              notes: "Sample credit card liability account",
              account_snapshots: [
                {
                  recorded_on: "2026-03-15",
                  balance: "-640.00",
                  available_balance: nil,
                  notes: "Sample statement balance"
                }
              ]
            }
          ],
          account_activity: [
            {
              account: "Example Visa",
              original_filename: "sample-account-activity.csv",
              header_row_number: 1,
              column_mapping: {
                transaction_on: "Transaction Date",
                posted_on: "Post Date",
                description: "Description",
                raw_amount: "Amount",
                category: "Category"
              },
              amount_strategy: "charges_are_negative",
              rows_count: 1,
              imported_count: 1,
              duplicate_count: 0,
              warning_messages: [],
              started_on: "2026-03-10",
              ended_on: "2026-03-10",
              metadata: {
                headers: [ "Transaction Date", "Post Date", "Description", "Category", "Amount" ]
              },
              created_at: "2026-03-10T12:00:00Z",
              updated_at: "2026-03-10T12:00:00Z",
              account_activities: [
                {
                  transaction_on: "2026-03-10",
                  posted_on: "2026-03-11",
                  description: "Sample Merchant 001",
                  category: "Utilities",
                  activity_type: "Sale",
                  memo: nil,
                  raw_amount: "-48.25",
                  amount: "48.25",
                  account_delta: "-48.25",
                  row_number: 2,
                  fingerprint: "sample-account-activity-fingerprint-1",
                  raw_payload: {
                    "Transaction Date" => "03/10/2026",
                    "Post Date" => "03/11/2026",
                    "Description" => "Sample Merchant 001",
                    "Category" => "Utilities",
                    "Amount" => "-48.25"
                  },
                  created_at: "2026-03-10T12:00:00Z",
                  updated_at: "2026-03-10T12:00:00Z"
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
end
