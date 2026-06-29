require "rails_helper"

RSpec.describe Recurring::MonthTemplateCoverage do
  it "counts same-month entries on different dates as alternate coverage" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 6, 1), label: "June 2026")
    bill = create(:monthly_bill,
                  user: user,
                  name: "WSSC Water",
                  kind: :variable_bill,
                  due_day: 20,
                  account: "Checking")
    entry = create(:expense_entry,
                   budget_month: budget_month,
                   user: user,
                   occurred_on: Date.new(2026, 6, 8),
                   section: :manual,
                   category: "Variable Bill",
                   payee: "WSSC Water",
                   planned_amount: 452.71,
                   actual_amount: 452.71,
                   account: "Checking",
                   status: :paid,
                   source_file: "manual")

    summary = described_class.new(template: bill, budget_month: budget_month, entries: [ entry ]).summary

    expect(summary).to include(total: 1, matched: 1, remaining: 0, complete: true, alternate_count: 1)
    expect(summary.fetch(:previews)).to be_empty
    expect(summary.fetch(:alternate_previews).first).to include(
      payee: "WSSC Water",
      occurred_on: Date.new(2026, 6, 20),
      matched_on: Date.new(2026, 6, 8),
      planned_amount: 452.71
    )
  end

  it "uses one alternate entry for only one scheduled occurrence" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 6, 1), label: "June 2026")
    schedule = create(:pay_schedule,
                      user: user,
                      name: "Quria",
                      cadence: :semimonthly,
                      amount: 2_600,
                      first_pay_on: Date.new(2026, 6, 1),
                      day_of_month_one: 15,
                      day_of_month_two: 30,
                      account: "Checking")
    entry = create(:expense_entry,
                   budget_month: budget_month,
                   user: user,
                   occurred_on: Date.new(2026, 6, 23),
                   section: :income,
                   category: "Paycheck",
                   payee: "Quria",
                   planned_amount: 2_600,
                   actual_amount: 2_600,
                   account: "Checking",
                   status: :paid,
                   source_file: "manual")

    summary = described_class.new(template: schedule, budget_month: budget_month, entries: [ entry ]).summary

    expect(summary).to include(total: 2, matched: 1, remaining: 1, complete: false, alternate_count: 1)
    expect(summary.fetch(:previews).size).to eq(1)
  end
end
