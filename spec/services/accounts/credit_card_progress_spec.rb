require "rails_helper"

RSpec.describe Accounts::CreditCardProgress do
  it "summarizes month-to-date card additions, payments, and payoff progress" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    card = create(:account, user: user, name: "Rewards Visa", kind: :credit_card)
    june = create(:budget_month, user: user, month_on: Date.new(2026, 6, 1), label: "June 2026")
    may = create(:budget_month, user: user, month_on: Date.new(2026, 5, 1), label: "May 2026")
    create(:account_snapshot, account: card, recorded_on: Date.new(2026, 6, 1), balance: -1_000)

    create(:expense_entry,
      budget_month: june,
      user: user,
      source_account: card,
      occurred_on: Date.new(2026, 6, 4),
      section: :variable,
      status: :paid,
      actual_amount: 125)

    create(:expense_entry,
      budget_month: june,
      user: user,
      source_account: checking,
      destination_account: card,
      occurred_on: Date.new(2026, 6, 10),
      section: :debt,
      status: :paid,
      actual_amount: 325)

    create(:expense_entry,
      budget_month: june,
      user: user,
      source_account: checking,
      destination_account: card,
      occurred_on: Date.new(2026, 6, 20),
      section: :debt,
      status: :planned,
      planned_amount: 75)

    create(:expense_entry,
      budget_month: may,
      user: user,
      source_account: card,
      occurred_on: Date.new(2026, 5, 28),
      section: :variable,
      status: :paid,
      actual_amount: 50)

    balance_summary = Accounts::BalanceHistory.new(account: card, as_of: Date.new(2026, 6, 15)).call.fetch(:summary)

    progress = described_class.new(
      account: card,
      balance_summary: balance_summary,
      as_of: Date.new(2026, 6, 15)
    ).call

    expect(progress[:month_label]).to eq("June 2026")
    expect(progress[:added_this_month]).to eq(125.to_d)
    expect(progress[:paid_down_this_month]).to eq(325.to_d)
    expect(progress[:net_paydown_this_month]).to eq(200.to_d)
    expect(progress[:starting_debt]).to eq(1_000.to_d)
    expect(progress[:current_debt]).to eq(800.to_d)
    expect(progress[:projected_debt]).to eq(725.to_d)
    expect(progress[:progress_percent]).to eq(20)
    expect(progress[:planned_payment_remaining_this_month]).to eq(75.to_d)
  end

  it "asks for a snapshot before calculating payoff progress" do
    user = create(:user)
    card = create(:account, user: user, name: "Rewards Visa", kind: :credit_card)
    balance_summary = Accounts::BalanceHistory.new(account: card, as_of: Date.new(2026, 6, 15)).call.fetch(:summary)

    progress = described_class.new(
      account: card,
      balance_summary: balance_summary,
      as_of: Date.new(2026, 6, 15)
    ).call

    expect(progress[:snapshot_needed?]).to be(true)
    expect(progress[:progress_percent]).to be_nil
  end
end
