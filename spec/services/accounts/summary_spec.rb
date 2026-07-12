require "rails_helper"

RSpec.describe Accounts::Summary do
  it "builds shared account summary data" do
    user = create(:user)
    checking = create(:account, user:, name: "Checking", kind: :checking, include_in_net_worth: true)
    card = create(:account, user:, name: "Credit Card", kind: :credit_card, include_in_net_worth: true)
    create(:account_snapshot, account: checking, recorded_on: Date.current - 1.day, balance: 2_500)
    create(:account_snapshot, account: card, recorded_on: Date.current - 2.days, balance: -400)

    summary = described_class.new(user:, include_trend: true).call

    expect(summary[:accounts]).to match_array([ checking, card ])
    expect(summary[:net_worth_accounts]).to match_array([ checking, card ])
    expect(summary[:assets_total]).to eq(2500.to_d)
    expect(summary[:liabilities_total]).to eq(400.to_d)
    expect(summary[:net_worth_total]).to eq(2100.to_d)
    expect(summary[:account_balance_rows].map { |row| row[:account] }).to match_array([ checking, card ])
    expect(summary[:latest_balance_source].account).to eq(checking)
    expect(summary[:accounts_with_balance_sources_count]).to eq(2)
    expect(summary[:accounts_missing_balance_sources_count]).to eq(0)
    expect(summary[:accounts_with_snapshots_count]).to eq(2)
    expect(summary[:accounts_missing_snapshots_count]).to eq(0)
    expect(summary[:trend_labels]).not_to be_empty
    expect(summary[:trend_values]).not_to be_empty
  end

  it "uses imported institution balances in account totals and rows" do
    user = create(:user)
    checking = create(:account, user:, name: "Checking", kind: :checking, include_in_net_worth: true)
    card = create(:account, user:, name: "Credit Card", kind: :credit_card, include_in_net_worth: true)
    create(:account_snapshot, account: checking, recorded_on: Date.new(2026, 7, 1), balance: 1_000)
    create(:account_snapshot, account: card, recorded_on: Date.new(2026, 7, 1), balance: -100)
    checking_import = create(
      :account_activity_import,
      account: checking,
      metadata: {
        institution_balance: "2500.00",
        institution_balance_as_of: "2026-07-02"
      }
    )
    card_import = create(
      :account_activity_import,
      account: card,
      metadata: {
        institution_balance: "-700.00",
        institution_balance_as_of: "2026-07-03"
      }
    )
    create(:account_activity, account_activity_import: checking_import, account: checking, transaction_on: Date.new(2026, 7, 4), amount: 50, account_delta: -50)
    create(:account_activity, account_activity_import: card_import, account: card, transaction_on: Date.new(2026, 7, 4), amount: 25, account_delta: -25)

    summary = described_class.new(user:, include_trend: false).call
    rows = summary.fetch(:account_balance_rows).index_by { |row| row.fetch(:account) }

    expect(summary[:assets_total]).to eq(2450.to_d)
    expect(summary[:liabilities_total]).to eq(725.to_d)
    expect(summary[:net_worth_total]).to eq(1725.to_d)
    expect(rows.fetch(checking)).to include(current_balance: 2450.to_d, source_label: "Institution import", activity_through_on: Date.new(2026, 7, 4), last_updated_on: Date.new(2026, 7, 4))
    expect(rows.fetch(card)).to include(current_balance: -725.to_d, source_label: "Institution import", activity_through_on: Date.new(2026, 7, 4), last_updated_on: Date.new(2026, 7, 4))
    expect(summary[:latest_balance_source].account).to eq(card)
  end

  it "marks imported rows without a balance source as unresolved" do
    user = create(:user)
    card = create(:account, user:, name: "Store Card", kind: :credit_card, include_in_net_worth: true)
    import = create(:account_activity_import, account: card)
    create(:account_activity, account_activity_import: import, account: card, transaction_on: Date.new(2026, 7, 4), amount: 650, account_delta: -650)

    summary = described_class.new(user:, include_trend: false).call
    row = summary.fetch(:account_balance_rows).first

    expect(summary[:liabilities_total]).to eq(0.to_d)
    expect(row).to include(
      account: card,
      current_balance: 0.to_d,
      source_label: "No balance source",
      source_type: :none,
      imported_activity_count: 1,
      balance_available: false
    )
  end
end
