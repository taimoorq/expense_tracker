require "rails_helper"

RSpec.describe Accounts::PeriodBalance do
  it "uses institution balances ahead of snapshots and linked entries for the period" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 7, 1), label: "July 2026")
    create(:account_snapshot, account: checking, recorded_on: Date.new(2026, 7, 1), balance: 1_000)
    import = create(
      :account_activity_import,
      account: checking,
      metadata: {
        institution_balance: "2200.00",
        institution_balance_as_of: "2026-07-10"
      }
    )
    create(:account_activity, account_activity_import: import, account: checking, transaction_on: Date.new(2026, 7, 12), amount: 25, account_delta: -25)
    create(:expense_entry, budget_month: month, user: user, source_account: checking, occurred_on: Date.new(2026, 7, 13), section: :fixed, status: :paid, actual_amount: 100)

    balance = described_class.new(account: checking, period_start: Date.new(2026, 7, 1), period_end: Date.new(2026, 7, 31)).call

    expect(balance.balance_source).to eq(:institution_import)
    expect(balance.starting_balance).to eq(2_200.to_d)
    expect(balance.paid_delta).to eq(-25.to_d)
    expect(balance.current_balance).to eq(2_175.to_d)
    expect(balance.activity_through_on).to eq(Date.new(2026, 7, 12))
  end

  it "uses activity-only imports from a prior snapshot when the period has imported rows" do
    user = create(:user)
    card = create(:account, user: user, name: "Rewards Card", kind: :credit_card)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 7, 1), label: "July 2026")
    create(:account_snapshot, account: card, recorded_on: Date.new(2026, 6, 30), balance: -500)
    import = create(:account_activity_import, account: card)
    create(:account_activity, account_activity_import: import, account: card, transaction_on: Date.new(2026, 7, 5), amount: 40, account_delta: -40)
    create(:expense_entry, budget_month: month, user: user, source_account: card, occurred_on: Date.new(2026, 7, 6), section: :variable, status: :paid, actual_amount: 100)

    balance = described_class.new(account: card, period_start: Date.new(2026, 7, 1), period_end: Date.new(2026, 7, 31)).call

    expect(balance.balance_source).to eq(:imported_activity)
    expect(balance.starting_balance).to eq(-500.to_d)
    expect(balance.paid_delta).to eq(-40.to_d)
    expect(balance.current_balance).to eq(-540.to_d)
    expect(balance.paid_entries_count).to eq(1)
  end

  it "falls back to snapshots and linked entries when a period has no imported rows" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    july = create(:budget_month, user: user, month_on: Date.new(2026, 7, 1), label: "July 2026")
    august = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1), label: "August 2026")
    create(:account_snapshot, account: checking, recorded_on: Date.new(2026, 6, 30), balance: 1_000)
    import = create(:account_activity_import, account: checking)
    create(:account_activity, account_activity_import: import, account: checking, transaction_on: Date.new(2026, 7, 5), amount: 40, account_delta: -40)
    create(:expense_entry, budget_month: july, user: user, source_account: checking, occurred_on: Date.new(2026, 7, 20), section: :income, status: :paid, actual_amount: 200)
    create(:expense_entry, budget_month: august, user: user, source_account: checking, occurred_on: Date.new(2026, 8, 5), section: :fixed, status: :paid, actual_amount: 100)

    balance = described_class.new(account: checking, period_start: Date.new(2026, 8, 1), period_end: Date.new(2026, 8, 31)).call

    expect(balance.balance_source).to eq(:snapshot)
    expect(balance.starting_balance).to eq(1_200.to_d)
    expect(balance.paid_delta).to eq(-100.to_d)
    expect(balance.current_balance).to eq(1_100.to_d)
  end

  it "does not turn activity-only imports into period balances without a trusted source" do
    user = create(:user)
    card = create(:account, user: user, name: "Store Card", kind: :credit_card)
    import = create(:account_activity_import, account: card)
    create(:account_activity, account_activity_import: import, account: card, transaction_on: Date.new(2026, 7, 5), amount: 650, account_delta: -650)

    balance = described_class.new(account: card, period_start: Date.new(2026, 7, 1), period_end: Date.new(2026, 7, 31)).call

    expect(balance.balance_source).to eq(:none)
    expect(balance.balance_available).to be(false)
    expect(balance.current_balance).to eq(0.to_d)
    expect(balance.paid_entries_count).to eq(0)
  end
end
