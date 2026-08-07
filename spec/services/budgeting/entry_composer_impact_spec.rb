require "rails_helper"

RSpec.describe Budgeting::EntryComposerImpact do
  it "shows the normalized month and two-sided account impact" do
    user = create(:user)
    checking = create(:account, user: user, kind: :checking)
    card = create(:account, user: user, kind: :credit_card)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    entry = build(
      :expense_entry,
      budget_month: month,
      section: :debt,
      status: :paid,
      planned_amount: 125,
      actual_amount: 120,
      source_account: checking,
      destination_account: card
    )

    result = described_class.call(expense_entry: entry)

    expect(result.amount).to eq(120.to_d)
    expect(result.month_delta).to eq(-120.to_d)
    expect(result.account_lines).to contain_exactly(
      { account: checking, delta: -120.to_d, movement_type: "bank_paid_out" },
      { account: card, delta: 120.to_d, movement_type: "credit_card_paid" }
    )
  end

  it "shows no financial impact for a skipped entry" do
    month = build(:budget_month, month_on: Date.new(2026, 3, 1), label: "March 2026")
    entry = build(:expense_entry, budget_month: month, status: :skipped, planned_amount: 75)

    result = described_class.call(expense_entry: entry)

    expect(result.amount).to eq(75.to_d)
    expect(result.month_delta).to eq(0.to_d)
    expect(result.month_label).to eq("No change to March 2026")
  end
end
