require "rails_helper"

RSpec.describe GenerateMonthPaychecks do
  it "creates paycheck entries for the month and avoids duplicates on rerun" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    create(:pay_schedule,
      user: user,
      name: "Acme Payroll",
      cadence: :semimonthly,
      first_pay_on: Date.new(2026, 1, 15),
      day_of_month_one: 15,
      day_of_month_two: 30,
      amount: 2500)

    first_run = described_class.new(budget_month: budget_month).call
    second_run = described_class.new(budget_month: budget_month).call

    expect(first_run).to eq(2)
    expect(second_run).to eq(0)
    expect(budget_month.expense_entries.where(source_file: "pay_schedule").count).to eq(2)
  end
end
