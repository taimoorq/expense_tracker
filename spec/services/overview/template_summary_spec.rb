require "rails_helper"

RSpec.describe Overview::TemplateSummary do
  it "tracks template counts, linked totals, and completed monthly actions" do
    user = create(:user)
    account = create(:account, user:, name: "Checking")
    liability_account = create(:account, user:, name: "Visa Account", kind: :credit_card)
    month = create(:budget_month, user:, month_on: Date.new(2026, 3, 1), label: "March 2026")

    create(:pay_schedule,
      user: user,
      name: "Employer",
      amount: 2_500,
      first_pay_on: Date.new(2026, 3, 1),
      day_of_month_one: 15,
      linked_account: account)
    create(:subscription, user: user, name: "Netflix", amount: 19.99, due_day: 8, account: "Visa")
    create(:credit_card, user: user, name: "Visa", minimum_payment: 40, due_day: 20, payment_account: account, linked_account: liability_account)

    create(:expense_entry,
      budget_month: month,
      user: user,
      occurred_on: Date.new(2026, 3, 15),
      section: :income,
      category: "Paycheck",
      payee: "Employer",
      planned_amount: 2_500,
      status: :planned,
      account: "Checking")
    create(:expense_entry,
      budget_month: month,
      user: user,
      occurred_on: Date.new(2026, 3, 20),
      section: :debt,
      category: "Credit Card",
      payee: "Visa",
      planned_amount: 60,
      status: :planned,
      account: "Checking")

    summary = described_class.new(user: user, current_month: month, current_month_entries: month.expense_entries.to_a).call

    expect(summary[:template_total]).to eq(3)
    expect(summary[:linked_template_total]).to eq(2)
    expect(summary[:template_actions_completed]).to eq(2)
    expect(summary[:template_counts]).to include(pay_schedules: 1, subscriptions: 1, credit_cards: 1)
  end
end
