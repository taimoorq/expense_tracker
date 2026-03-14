require "rails_helper"

RSpec.describe Account, type: :model do
  it "uses the latest snapshot balance for display" do
    account = create(:account)
    create(:account_snapshot, account: account, recorded_on: Date.new(2026, 3, 1), balance: 1200)
    create(:account_snapshot, account: account, recorded_on: Date.new(2026, 3, 15), balance: 1800)

    expect(account.latest_balance.to_d).to eq(1800.to_d)
    expect(account.asset?).to be(true)
  end

  it "identifies liability account kinds" do
    account = build(:account, kind: :credit_card)

    expect(account.liability?).to be(true)
    expect(account.asset?).to be(false)
  end
end
