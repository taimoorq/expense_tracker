require "rails_helper"

RSpec.describe Overview::ReviewSummary do
  it "counts review items and linked entry state from month entries" do
    user = create(:user)
    account = create(:account, user:, name: "Checking")
    month = create(:budget_month, user:, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))

    create(:expense_entry,
      budget_month: month,
      user: user,
      occurred_on: Date.current,
      section: :fixed,
      category: "Utilities",
      payee: "Power Company",
      planned_amount: 95,
      account: nil,
      status: :planned)
    create(:expense_entry,
      budget_month: month,
      user: user,
      occurred_on: nil,
      section: :manual,
      category: nil,
      payee: nil,
      planned_amount: 20,
      account: nil,
      status: :planned)
    create(:expense_entry,
      budget_month: month,
      user: user,
      occurred_on: Date.current,
      section: :income,
      category: "Paycheck",
      payee: "Employer",
      planned_amount: 2_000,
      actual_amount: nil,
      status: :paid,
      source_account: account)

    summary = described_class.new(entries: month.expense_entries.to_a, today: Date.current).call

    expect(summary[:due_planned_count]).to eq(1)
    expect(summary[:missing_details_count]).to eq(1)
    expect(summary[:paid_missing_actual_count]).to eq(1)
    expect(summary[:review_attention_count]).to eq(3)
    expect(summary[:linked_entries_count]).to eq(1)
    expect(summary[:linked_paid_entries_count]).to eq(1)
  end
end
