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
end
