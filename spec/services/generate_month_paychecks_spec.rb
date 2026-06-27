require "rails_helper"

RSpec.describe GenerateMonthPaychecks do
  it "creates paycheck entries for the month and avoids duplicates on rerun" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    checking = create(:account, user: user, name: "Checking")
    create(:pay_schedule,
      user: user,
      name: "Acme Payroll",
      cadence: :semimonthly,
      first_pay_on: Date.new(2026, 1, 15),
      day_of_month_one: 15,
      day_of_month_two: 30,
      amount: 2500,
      linked_account: checking,
      account: "Legacy")

    first_run = described_class.new(budget_month: budget_month).call
    second_run = described_class.new(budget_month: budget_month).call
    generated_entries = budget_month.expense_entries.where(source_file: "pay_schedule")

    expect(first_run).to eq(2)
    expect(second_run).to eq(0)
    expect(generated_entries.count).to eq(2)
    expect(generated_entries.pluck(:account).uniq).to eq([ "Checking" ])
    expect(generated_entries.pluck(:source_template_type).uniq).to eq([ "PaySchedule" ])
    expect(generated_entries.pluck(:source_template_id).uniq).to eq([ user.pay_schedules.find_by!(name: "Acme Payroll").id ])
  end

  it "stops an ended schedule and starts a replacement schedule in the next year" do
    user = create(:user)
    december = create(:budget_month, user: user, month_on: Date.new(2026, 12, 1), label: "December 2026")
    january = create(:budget_month, user: user, month_on: Date.new(2027, 1, 1), label: "January 2027")

    create(:pay_schedule,
      user: user,
      name: "Acme Payroll",
      cadence: :semimonthly,
      first_pay_on: Date.new(2026, 1, 15),
      ends_on: Date.new(2026, 12, 31),
      day_of_month_one: 15,
      day_of_month_two: 30,
      weekend_adjustment: :no_adjustment,
      amount: 2500)

    create(:pay_schedule,
      user: user,
      name: "Acme Payroll",
      cadence: :monthly,
      first_pay_on: Date.new(2027, 1, 10),
      day_of_month_one: 10,
      weekend_adjustment: :no_adjustment,
      amount: 2850)

    expect(described_class.new(budget_month: december).call).to eq(2)
    expect(described_class.new(budget_month: january).call).to eq(1)

    december_entries = december.expense_entries.where(source_file: "pay_schedule").order(:occurred_on)
    january_entries = january.expense_entries.where(source_file: "pay_schedule").order(:occurred_on)

    expect(december_entries.pluck(:occurred_on, :planned_amount)).to eq([
      [ Date.new(2026, 12, 15), 2500.to_d ],
      [ Date.new(2026, 12, 30), 2500.to_d ]
    ])
    expect(january_entries.pluck(:occurred_on, :planned_amount)).to eq([
      [ Date.new(2027, 1, 10), 2850.to_d ]
    ])
  end
end
