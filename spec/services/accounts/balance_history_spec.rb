require "rails_helper"

RSpec.describe Accounts::BalanceHistory do
  it "summarizes current and projected balances from snapshots, paid entries, and planned entries" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    march = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    april = create(:budget_month, user: user, month_on: Date.new(2026, 4, 1), label: "April 2026")
    create(:account_snapshot, account: checking, recorded_on: Date.new(2026, 3, 10), balance: 1_000)

    create(:expense_entry,
      budget_month: march,
      user: user,
      source_account: checking,
      occurred_on: Date.new(2026, 3, 12),
      section: :income,
      status: :paid,
      actual_amount: 500)

    create(:expense_entry,
      budget_month: march,
      user: user,
      source_account: checking,
      occurred_on: Date.new(2026, 3, 20),
      section: :fixed,
      status: :paid,
      actual_amount: 125)

    create(:expense_entry,
      budget_month: april,
      user: user,
      source_account: checking,
      occurred_on: Date.new(2026, 4, 10),
      section: :fixed,
      status: :planned,
      planned_amount: 200)

    result = described_class.new(account: checking, as_of: Date.new(2026, 4, 1)).call
    summary = result.fetch(:summary)

    expect(summary[:base_balance]).to eq(1_000.to_d)
    expect(summary[:paid_delta]).to eq(375.to_d)
    expect(summary[:planned_delta]).to eq(-200.to_d)
    expect(summary[:current_balance]).to eq(1_375.to_d)
    expect(summary[:projected_balance]).to eq(1_175.to_d)

    march_row = result.fetch(:rows).find { |row| row[:month_on] == Date.new(2026, 3, 1) }
    april_row = result.fetch(:rows).find { |row| row[:month_on] == Date.new(2026, 4, 1) }

    expect(march_row[:paid_delta]).to eq(375.to_d)
    expect(march_row[:starting_balance]).to eq(1_000.to_d)
    expect(march_row[:current_balance]).to eq(1_375.to_d)
    expect(april_row[:starting_balance]).to eq(1_375.to_d)
    expect(april_row[:planned_delta]).to eq(-200.to_d)
    expect(april_row[:projected_balance]).to eq(1_175.to_d)
  end

  it "treats credit card charges as added debt and destination payments as paydown" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    card = create(:account, user: user, name: "Rewards Visa", kind: :credit_card)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 5, 1), label: "May 2026")
    create(:account_snapshot, account: card, recorded_on: Date.new(2026, 5, 1), balance: -800)

    create(:expense_entry,
      budget_month: month,
      user: user,
      source_account: card,
      occurred_on: Date.new(2026, 5, 5),
      section: :variable,
      status: :paid,
      actual_amount: 90)

    create(:expense_entry,
      budget_month: month,
      user: user,
      source_account: checking,
      destination_account: card,
      occurred_on: Date.new(2026, 5, 15),
      section: :debt,
      status: :paid,
      actual_amount: 250)

    create(:expense_entry,
      budget_month: month,
      user: user,
      source_account: checking,
      destination_account: card,
      occurred_on: Date.new(2026, 5, 25),
      section: :debt,
      status: :planned,
      planned_amount: 100)

    summary = described_class.new(account: card, as_of: Date.new(2026, 5, 20)).call.fetch(:summary)

    expect(summary[:paid_delta]).to eq(160.to_d)
    expect(summary[:planned_delta]).to eq(100.to_d)
    expect(summary[:current_balance]).to eq(-640.to_d)
    expect(summary[:projected_balance]).to eq(-540.to_d)
  end
end
