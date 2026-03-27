require "rails_helper"

RSpec.describe Accounts::Summary do
  it "builds shared account summary data" do
    user = create(:user)
    checking = create(:account, user:, name: "Checking", kind: :checking, include_in_net_worth: true)
    card = create(:account, user:, name: "Credit Card", kind: :credit_card, include_in_net_worth: true)
    create(:account_snapshot, account: checking, recorded_on: Date.current - 1.day, balance: 2_500)
    create(:account_snapshot, account: card, recorded_on: Date.current - 1.day, balance: -400)

    summary = described_class.new(user:, include_trend: true).call

    expect(summary[:accounts]).to match_array([ checking, card ])
    expect(summary[:net_worth_accounts]).to match_array([ checking, card ])
    expect(summary[:assets_total]).to eq(2500.to_d)
    expect(summary[:liabilities_total]).to eq(400.to_d)
    expect(summary[:net_worth_total]).to eq(2100.to_d)
    expect(summary[:accounts_with_snapshots_count]).to eq(2)
    expect(summary[:accounts_missing_snapshots_count]).to eq(0)
    expect(summary[:trend_labels]).not_to be_empty
    expect(summary[:trend_values]).not_to be_empty
  end
end
