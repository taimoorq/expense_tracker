require "rails_helper"

RSpec.describe Accounts::Summary do
  def count_select_queries
    count = 0
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      count += 1 if payload[:sql].to_s.match?(/\ASELECT/i) && payload[:name] != "SCHEMA"
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end

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
      imported_activity_through_on: Date.new(2026, 7, 4),
      last_updated_on: Date.new(2026, 7, 4),
      balance_available: false
    )
  end

  it "loads balance inputs in batches as account count grows" do
    user = create(:user)
    month = create(:budget_month, user:, month_on: Date.current.beginning_of_month)
    accounts = create_list(:account, 6, user: user)
    accounts.each do |account|
      create(:account_snapshot, account: account, recorded_on: Date.current - 1.day, balance: 100)
      create(:expense_entry, user:, budget_month: month, source_account: account, occurred_on: Date.current, status: :paid, actual_amount: 10)
    end

    queries = count_select_queries do
      described_class.new(user: user.reload, include_trend: true).call
    end

    expect(queries).to be <= 15
  end

  it "uses bounded target balance and trend queries after read cutover" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month)
    accounts = create_list(:account, 6, user: user, kind: :checking)
    accounts.each do |account|
      create(:account_snapshot, account: account, recorded_on: Date.current - 2.days, balance: 100)
      create(:expense_entry, user: user, budget_month: month, source_account: account, occurred_on: Date.current - 1.day, status: :paid, actual_amount: 10)
    end
    backfill = Platform::TargetBackfill::Runner.call(user: user)
    backfill.workspace.update!(target_writes_enabled: true, target_reads_enabled: true)

    payload = nil
    queries = count_select_queries { payload = described_class.new(user: user.reload, include_trend: true).call }

    expect(queries).to be <= 18
    expect(payload).to include(calculation_version: "target-v1", net_worth_total: 540.to_d)
    expect(payload[:trend_rows].last).to include(value: 540.0, coverage_count: 6, account_count: 6, complete: true)
  end
end
