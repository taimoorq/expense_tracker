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

  it "summarizes credit card balances from institution imports when available" do
    user = create(:user)
    card = create(:account, user: user, name: "Rewards Visa", kind: :credit_card)
    create(:account_snapshot, account: card, recorded_on: Date.new(2026, 7, 1), balance: -800)
    import = create(
      :account_activity_import,
      account: card,
      metadata: {
        institution_balance: "-1200.00",
        institution_balance_as_of: "2026-07-03"
      }
    )
    create(:account_activity, account_activity_import: import, account: card, transaction_on: Date.new(2026, 7, 4), amount: 40, account_delta: -40)

    summary = described_class.new(account: card, as_of: Date.new(2026, 7, 5)).call.fetch(:summary)

    expect(summary).to include(
      balance_source: :institution_import,
      balance_source_label: "Institution import",
      base_balance: -1200.to_d,
      paid_delta: -40.to_d,
      current_balance: -1240.to_d
    )
  end

  it "labels monthly rows with the source that applies to that period" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    july = create(:budget_month, user: user, month_on: Date.new(2026, 7, 1), label: "July 2026")
    august = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1), label: "August 2026")
    create(:account_snapshot, account: checking, recorded_on: Date.new(2026, 6, 30), balance: 1_000)
    import = create(:account_activity_import, account: checking)
    create(:account_activity, account_activity_import: import, account: checking, transaction_on: Date.new(2026, 7, 5), amount: 40, account_delta: -40)
    create(:expense_entry, budget_month: july, user: user, source_account: checking, occurred_on: Date.new(2026, 7, 20), section: :income, status: :paid, actual_amount: 200)
    create(:expense_entry, budget_month: august, user: user, source_account: checking, occurred_on: Date.new(2026, 8, 5), section: :fixed, status: :paid, actual_amount: 100)

    result = described_class.new(account: checking, as_of: Date.new(2026, 8, 15)).call
    july_row = result.fetch(:rows).find { |row| row[:month_on] == Date.new(2026, 7, 1) }
    august_row = result.fetch(:rows).find { |row| row[:month_on] == Date.new(2026, 8, 1) }

    expect(july_row).to include(
      balance_source: :imported_activity,
      paid_delta: -40.to_d,
      current_balance: 960.to_d,
      activity_through_on: Date.new(2026, 7, 5)
    )
    expect(august_row).to include(
      balance_source: :snapshot,
      starting_balance: 1_200.to_d,
      paid_delta: -100.to_d,
      current_balance: 1_100.to_d
    )
  end

  it "keeps monthly rows unresolved when imported rows have no trusted source" do
    user = create(:user)
    card = create(:account, user: user, name: "Store Card", kind: :credit_card)
    import = create(:account_activity_import, account: card)
    create(:account_activity, account_activity_import: import, account: card, transaction_on: Date.new(2026, 7, 5), amount: 650, account_delta: -650)

    row = described_class.new(account: card, as_of: Date.new(2026, 7, 31)).call.fetch(:rows).first

    expect(row).to include(
      balance_source: :none,
      balance_available: false,
      current_balance: 0.to_d,
      paid_entries_count: 0
    )
  end
end
