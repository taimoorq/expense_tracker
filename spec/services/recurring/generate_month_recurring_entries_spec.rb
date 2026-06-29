require "rails_helper"

RSpec.describe Recurring::GenerateMonthRecurringEntries do
  it "locks month generation while creating entries" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1))
    schedule = create(:pay_schedule, user: user, first_pay_on: Date.new(2026, 3, 15), day_of_month_one: 15, cadence: :monthly)

    expect(budget_month).to receive(:with_lock).and_call_original

    created = described_class.new(budget_month: budget_month, templates: [ schedule ]).call

    expect(created).to eq(1)
  end

  it "stores a durable generated entry key and uses it on rerun" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1))
    schedule = create(:pay_schedule, user: user, first_pay_on: Date.new(2026, 3, 15), day_of_month_one: 15, cadence: :monthly)
    generator = described_class.new(budget_month: budget_month, templates: [ schedule ])
    expected_key = schedule.generated_entry_key(month_on: budget_month.month_on, occurred_on: Date.new(2026, 3, 15))

    expect(generator.call).to eq(1)

    entry = budget_month.expense_entries.find_by!(payee: schedule.name)
    expect(entry.generated_entry_key).to eq(expected_key)

    expect(generator.call).to eq(0)
    expect(budget_month.expense_entries.where(generated_entry_key: expected_key).count).to eq(1)
  end

  it "treats an existing generated key as authoritative even if editable fields drift" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1))
    schedule = create(:pay_schedule, user: user, first_pay_on: Date.new(2026, 3, 15), day_of_month_one: 15, cadence: :monthly)
    generated_key = schedule.generated_entry_key(month_on: budget_month.month_on, occurred_on: Date.new(2026, 3, 15))

    create(
      :expense_entry,
      budget_month: budget_month,
      user: user,
      generated_entry_key: generated_key,
      occurred_on: Date.new(2026, 3, 15),
      section: :income,
      payee: "Edited payroll name",
      planned_amount: 10,
      source_file: "manual"
    )

    created = described_class.new(budget_month: budget_month, templates: [ schedule ]).call

    expect(created).to eq(0)
    expect(budget_month.expense_entries.where(generated_entry_key: generated_key).count).to eq(1)
  end

  it "does not create a duplicate when the scheduled item is already on another date in the month" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 6, 1), label: "June 2026")
    bill = create(:monthly_bill,
                  user: user,
                  name: "WSSC Water",
                  kind: :variable_bill,
                  due_day: 20,
                  account: "Checking")
    create(:expense_entry,
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

    created = described_class.new(budget_month: budget_month, templates: [ bill ]).call

    expect(created).to eq(0)
    expect(budget_month.expense_entries.where(payee: "WSSC Water").count).to eq(1)
  end

  it "does not let one alternate entry cover every similar occurrence" do
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
    create(:expense_entry,
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

    created = described_class.new(budget_month: budget_month, templates: [ schedule ]).call

    expect(created).to eq(1)
    expect(budget_month.expense_entries.where(payee: "Quria").count).to eq(2)
  end
end
