require "rails_helper"

RSpec.describe Recurring::TemplateMonthStatus do
  it "prefills the next missing occurrence and reports partial month coverage" do
    user = create(:user)
    checking = create(:account, user: user, kind: :checking, name: "Checking")
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    schedule = create(
      :pay_schedule,
      user: user,
      name: "Payroll",
      cadence: :semimonthly,
      amount: 2_000,
      first_pay_on: Date.new(2026, 1, 15),
      day_of_month_one: 15,
      day_of_month_two: 30,
      linked_account: checking
    )
    first_date, second_date = schedule.recurring_month_occurrences(budget_month.month_on)
    create(
      :expense_entry,
      budget_month: budget_month,
      occurred_on: first_date,
      section: :income,
      category: "Paycheck",
      payee: "Payroll",
      planned_amount: 2_000,
      source_template: schedule,
      source_file: "pay_schedule",
      source_account: checking
    )

    result = described_class.call(template: schedule, budget_month: budget_month)

    expect(result.status).to eq(:missing)
    expect(result.label).to include("1 of 2 already added")
    expect(result.prefill[:occurred_on]).to eq(second_date.iso8601)
    expect(result.prefill[:source_account_id]).to eq(checking.id)
    expect(result.extra_occurrence_required?).to be(false)
  end

  it "requires an extra-occurrence acknowledgement when the month is already covered" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    subscription = create(:subscription, user: user, name: "Netflix", amount: 19.99, due_day: 8)
    create(
      :expense_entry,
      budget_month: budget_month,
      occurred_on: Date.new(2026, 3, 8),
      section: :fixed,
      category: "Subscription",
      payee: "Netflix",
      planned_amount: 19.99,
      account: subscription.account,
      source_template: subscription,
      source_file: "subscription"
    )

    result = described_class.call(template: subscription, budget_month: budget_month)

    expect(result.status).to eq(:already_added)
    expect(result.extra_occurrence_required?).to be(true)
  end

  it "does not count an unsaved validation-failed entry as month coverage" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    subscription = create(:subscription, user: user, name: "Netflix", amount: 19.99, due_day: 8)
    budget_month.expense_entries.build(
      occurred_on: Date.new(2026, 3, 8),
      section: :fixed,
      category: "Subscription",
      payee: "Netflix",
      planned_amount: 19.99,
      source_template: subscription,
      source_file: "subscription"
    )

    result = described_class.call(template: subscription, budget_month: budget_month)

    expect(result.status).to eq(:missing)
    expect(result.extra_occurrence_required?).to be(false)
  end
end
