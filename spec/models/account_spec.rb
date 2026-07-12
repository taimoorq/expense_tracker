require "rails_helper"

RSpec.describe Account, type: :model do
  it "uses the latest snapshot balance for display" do
    account = create(:account)
    create(:account_snapshot, account: account, recorded_on: Date.new(2026, 3, 1), balance: 1200)
    create(:account_snapshot, account: account, recorded_on: Date.new(2026, 3, 15), balance: 1800)

    expect(account.latest_balance.to_d).to eq(1800.to_d)
    expect(account.asset?).to be(true)
  end

  it "adds paid entry activity after the latest snapshot to current balance" do
    user = create(:user)
    account = create(:account, user: user, name: "Checking")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    create(:account_snapshot, account: account, recorded_on: Date.new(2026, 3, 10), balance: 1000)

    create(:expense_entry,
           budget_month: month,
           user: user,
           source_account: account,
           occurred_on: Date.new(2026, 3, 12),
           section: :income,
           status: :paid,
           planned_amount: 400,
           actual_amount: 400)

    create(:expense_entry,
           budget_month: month,
           user: user,
           source_account: account,
           occurred_on: Date.new(2026, 3, 15),
           section: :fixed,
           status: :paid,
           planned_amount: 125,
           actual_amount: 125)

    expect(account.current_balance).to eq(1275.to_d)
    expect(account.display_balance).to eq(1275.to_d)
  end

  it "applies source charges and destination payments to credit card balances after the latest snapshot" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    card = create(:account, user: user, name: "Visa", kind: :credit_card)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 4, 1), label: "April 2026")
    create(:account_snapshot, account: card, recorded_on: Date.new(2026, 4, 1), balance: -1000)

    create(:expense_entry,
      budget_month: month,
      user: user,
      source_account: card,
      occurred_on: Date.new(2026, 4, 5),
      section: :variable,
      status: :paid,
      actual_amount: 125)

    create(:expense_entry,
      budget_month: month,
      user: user,
      source_account: checking,
      destination_account: card,
      occurred_on: Date.new(2026, 4, 20),
      section: :debt,
      status: :paid,
      actual_amount: 300)

    expect(card.current_balance(as_of: Date.new(2026, 4, 30))).to eq(-825.to_d)
  end

  it "uses an institution-reported credit card balance ahead of manual snapshots and budget entries" do
    user = create(:user)
    card = create(:account, user: user, name: "Visa", kind: :credit_card)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 7, 1), label: "July 2026")
    create(:account_snapshot, account: card, recorded_on: Date.new(2026, 7, 1), balance: -500)
    import = create(
      :account_activity_import,
      account: card,
      metadata: {
        institution_balance: "-1000.00",
        institution_balance_as_of: "2026-07-02"
      }
    )
    create(:account_activity, account_activity_import: import, account: card, transaction_on: Date.new(2026, 7, 3), amount: 25, account_delta: -25)
    create(:expense_entry, budget_month: month, user: user, source_account: checking, destination_account: card, occurred_on: Date.new(2026, 7, 4), section: :debt, status: :paid, actual_amount: 300)

    source = card.imported_card_balance_source(as_of: Date.new(2026, 7, 5))

    expect(source).to include(type: :institution_import, base_balance: -1000.to_d, activity_delta: -25.to_d)
    expect(card.current_balance(as_of: Date.new(2026, 7, 5))).to eq(-1025.to_d)
  end

  it "uses an institution-reported bank balance ahead of manual snapshots" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    create(:account_snapshot, account: checking, recorded_on: Date.new(2026, 7, 1), balance: 500)
    import = create(
      :account_activity_import,
      account: checking,
      metadata: {
        institution_balance: "1200.00",
        institution_balance_as_of: "2026-07-02"
      }
    )
    create(:account_activity, account_activity_import: import, account: checking, transaction_on: Date.new(2026, 7, 3), amount: 50, account_delta: -50)

    expect(checking.current_balance(as_of: Date.new(2026, 7, 5))).to eq(1150.to_d)
  end

  it "rolls credit card snapshots forward with imported institution rows when no reported balance exists" do
    user = create(:user)
    card = create(:account, user: user, name: "Visa", kind: :credit_card)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 7, 1), label: "July 2026")
    create(:account_snapshot, account: card, recorded_on: Date.new(2026, 7, 1), balance: -500)
    import = create(:account_activity_import, account: card)
    create(:account_activity, account_activity_import: import, account: card, transaction_on: Date.new(2026, 7, 3), amount: 25, account_delta: -25)
    create(:expense_entry, budget_month: month, user: user, source_account: card, occurred_on: Date.new(2026, 7, 4), section: :variable, status: :paid, actual_amount: 300)

    source = card.imported_card_balance_source(as_of: Date.new(2026, 7, 5))

    expect(source).to include(type: :imported_activity, base_balance: -500.to_d, activity_delta: -25.to_d)
    expect(card.current_balance(as_of: Date.new(2026, 7, 5))).to eq(-525.to_d)
  end

  it "identifies liability account kinds" do
    account = build(:account, kind: :credit_card)

    expect(account.liability?).to be(true)
    expect(account.asset?).to be(false)
  end
end
