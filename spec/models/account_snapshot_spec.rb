require "rails_helper"

RSpec.describe AccountSnapshot, type: :model do
  it "requires a unique recorded_on date per account" do
    account = create(:account)
    create(:account_snapshot, account: account, recorded_on: Date.new(2026, 3, 14))

    duplicate_snapshot = build(:account_snapshot, account: account, recorded_on: Date.new(2026, 3, 14))

    expect(duplicate_snapshot).not_to be_valid
    expect(duplicate_snapshot.errors[:recorded_on]).to include("has already been taken")
  end

  it "delegates the user through the account" do
    account = create(:account)
    snapshot = create(:account_snapshot, account: account)

    expect(snapshot.user).to eq(account.user)
  end
end
