require "rails_helper"

RSpec.describe Accounts::MovementDrilldown do
  it "returns entries for the selected account movement" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    card = create(:account, user: user, name: "Rewards Visa", kind: :credit_card)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 4, 1), label: "April 2026")

    paid_card_payment = create(:expense_entry,
      budget_month: budget_month,
      user: user,
      source_account: checking,
      destination_account: card,
      section: :debt,
      status: :paid,
      actual_amount: 300,
      payee: "Rewards Visa")

    create(:expense_entry,
      budget_month: budget_month,
      user: user,
      source_account: checking,
      destination_account: card,
      section: :debt,
      status: :planned,
      planned_amount: 150,
      payee: "Rewards Visa")

    result = described_class.new(
      budget_month: budget_month,
      account: card,
      movement_type: "credit_card_paid"
    ).call

    expect(result[:title]).to eq("Credit card payments made")
    expect(result[:entries]).to eq([ paid_card_payment ])
    expect(result[:total]).to eq(300.to_d)
    expect(result[:entry_count]).to eq(1)
  end
end
