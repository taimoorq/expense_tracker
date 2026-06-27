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
end
