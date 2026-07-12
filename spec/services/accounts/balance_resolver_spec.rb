require "rails_helper"

RSpec.describe Accounts::BalanceResolver do
  it "falls back to manual snapshots and paid linked entries" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 7, 1), label: "July 2026")
    create(:account_snapshot, account: checking, recorded_on: Date.new(2026, 7, 1), balance: 1_000)
    create(:expense_entry, budget_month: month, user: user, source_account: checking, occurred_on: Date.new(2026, 7, 2), section: :income, status: :paid, actual_amount: 200)
    create(:expense_entry, budget_month: month, user: user, source_account: checking, occurred_on: Date.new(2026, 7, 3), section: :fixed, status: :paid, actual_amount: 50)

    balance = described_class.new(account: checking, as_of: Date.new(2026, 7, 5)).call

    expect(balance.balance_source).to eq(:snapshot)
    expect(balance.balance_source_label).to eq("Manual snapshot")
    expect(balance.current_balance).to eq(1_150.to_d)
    expect(balance.paid_delta).to eq(150.to_d)
  end

  it "uses institution balances for bank accounts and rolls forward imported activity" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    create(:account_snapshot, account: checking, recorded_on: Date.new(2026, 7, 1), balance: 1_000)
    import = create(
      :account_activity_import,
      account: checking,
      metadata: {
        institution_balance: "2200.00",
        institution_balance_as_of: "2026-07-02"
      }
    )
    create(:account_activity, account_activity_import: import, account: checking, transaction_on: Date.new(2026, 7, 3), amount: 25, account_delta: -25)

    balance = described_class.new(account: checking, as_of: Date.new(2026, 7, 5)).call

    expect(balance.balance_source).to eq(:institution_import)
    expect(balance.balance_source_label).to eq("Institution import")
    expect(balance.balance_source_recorded_on).to eq(Date.new(2026, 7, 2))
    expect(balance.base_balance).to eq(2_200.to_d)
    expect(balance.paid_delta).to eq(-25.to_d)
    expect(balance.activity_through_on).to eq(Date.new(2026, 7, 3))
    expect(balance.current_balance).to eq(2_175.to_d)
  end

  it "does not turn activity into a balance without a trusted source" do
    user = create(:user)
    card = create(:account, user: user, name: "Store Card", kind: :credit_card)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 7, 1), label: "July 2026")
    import = create(:account_activity_import, account: card)
    create(:account_activity, account_activity_import: import, account: card, transaction_on: Date.new(2026, 7, 3), amount: 650, account_delta: -650)
    create(:expense_entry, budget_month: month, user: user, source_account: card, occurred_on: Date.new(2026, 7, 4), section: :variable, status: :paid, actual_amount: 40)

    balance = described_class.new(account: card, as_of: Date.new(2026, 7, 5)).call

    expect(balance.balance_source).to eq(:none)
    expect(balance.balance_available).to be(false)
    expect(balance.current_balance).to eq(0.to_d)
    expect(balance.paid_delta).to eq(0.to_d)
    expect(balance.paid_entries_count).to eq(0)
    expect(balance.activity_through_on).to be_nil
  end

  it "uses the latest imported row as the activity-through date after a snapshot" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    create(:account_snapshot, account: checking, recorded_on: Date.new(2026, 6, 19), balance: 4_000)
    import = create(:account_activity_import, account: checking)
    create(:account_activity, account_activity_import: import, account: checking, transaction_on: Date.new(2026, 6, 20), amount: 10, account_delta: -10)
    create(:account_activity, account_activity_import: import, account: checking, transaction_on: Date.new(2026, 6, 30), amount: 100, account_delta: 100)

    balance = described_class.new(account: checking, as_of: Date.new(2026, 7, 5)).call

    expect(balance.balance_source).to eq(:imported_activity)
    expect(balance.balance_source_recorded_on).to eq(Date.new(2026, 6, 19))
    expect(balance.activity_through_on).to eq(Date.new(2026, 6, 30))
    expect(balance.current_balance).to eq(4_090.to_d)
  end

  it "ignores future snapshots and institution imports for an earlier as-of date" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    create(:account_snapshot, account: checking, recorded_on: Date.new(2026, 7, 1), balance: 1_000)
    create(:account_snapshot, account: checking, recorded_on: Date.new(2026, 7, 10), balance: 9_000)
    create(
      :account_activity_import,
      account: checking,
      metadata: {
        institution_balance: "2200.00",
        institution_balance_as_of: "2026-07-08"
      }
    )

    balance = described_class.new(account: checking, as_of: Date.new(2026, 7, 5)).call

    expect(balance.balance_source).to eq(:snapshot)
    expect(balance.balance_source_recorded_on).to eq(Date.new(2026, 7, 1))
    expect(balance.current_balance).to eq(1_000.to_d)
  end

  it "falls back to snapshots when imported rows do not apply after the trusted source" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 7, 1), label: "July 2026")
    import = create(:account_activity_import, account: checking)
    create(:account_activity, account_activity_import: import, account: checking, transaction_on: Date.new(2026, 6, 20), amount: 40, account_delta: -40)
    create(:account_snapshot, account: checking, recorded_on: Date.new(2026, 7, 1), balance: 1_000)
    create(:expense_entry, budget_month: month, user: user, source_account: checking, occurred_on: Date.new(2026, 7, 5), section: :income, status: :paid, actual_amount: 200)

    balance = described_class.new(account: checking, as_of: Date.new(2026, 7, 6)).call

    expect(balance.balance_source).to eq(:snapshot)
    expect(balance.paid_delta).to eq(200.to_d)
    expect(balance.current_balance).to eq(1_200.to_d)
  end
end
