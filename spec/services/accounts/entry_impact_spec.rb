require "rails_helper"

RSpec.describe Accounts::EntryImpact do
  it "classifies source and destination account movement from the same entry" do
    user = create(:user)
    checking = create(:account, user: user, kind: :checking)
    card = create(:account, user: user, kind: :credit_card)
    month = create(:budget_month, user: user)
    entry = create(
      :expense_entry,
      budget_month: month,
      user: user,
      source_account: checking,
      destination_account: card,
      section: :debt,
      status: :paid,
      actual_amount: 125
    )

    checking_impact = described_class.new(account: checking, entry: entry)
    card_impact = described_class.new(account: card, entry: entry)

    expect(checking_impact.delta).to eq(-125.to_d)
    expect(checking_impact.movement_type).to eq("bank_paid_out")
    expect(card_impact.delta).to eq(125.to_d)
    expect(card_impact.movement_type).to eq("credit_card_paid")
  end

  it "ignores skipped entries for movement summaries and account deltas" do
    user = create(:user)
    checking = create(:account, user: user, kind: :checking)
    month = create(:budget_month, user: user)
    entry = create(
      :expense_entry,
      budget_month: month,
      user: user,
      source_account: checking,
      section: :fixed,
      status: :skipped,
      planned_amount: 75
    )

    impact = described_class.new(account: checking, entry: entry)

    expect(impact.delta).to eq(0.to_d)
    expect(impact.movement_type).to be_nil
  end
end
