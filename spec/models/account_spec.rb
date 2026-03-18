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

  it "identifies liability account kinds" do
    account = build(:account, kind: :credit_card)

    expect(account.liability?).to be(true)
    expect(account.asset?).to be(false)
  end
end
