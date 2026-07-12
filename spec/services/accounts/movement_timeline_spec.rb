require "rails_helper"

RSpec.describe Accounts::MovementTimeline do
  let(:as_of) { Date.new(2026, 7, 10) }
  let(:user) { create(:user) }

  it "uses imported institution activity instead of linked paid entries in a covered bucket" do
    account = create(:account, user: user, kind: :checking)
    month = create(:budget_month, user: user, month_on: as_of.beginning_of_month, label: "July 2026")
    activity_import = create(
      :account_activity_import,
      account: account,
      started_on: as_of.beginning_of_month,
      ended_on: as_of
    )
    create(:account_activity, account: account, account_activity_import: activity_import, transaction_on: as_of - 2.days, account_delta: -40, amount: 40)
    create(:account_activity, account: account, account_activity_import: activity_import, transaction_on: as_of - 1.day, account_delta: 100, amount: 100)
    create(:expense_entry, user: user, budget_month: month, source_account: account, status: :paid, section: :fixed, occurred_on: as_of - 1.day, actual_amount: 900)

    bucket = described_class.new(account: account, range: "6m", as_of: as_of).call.fetch(:buckets).last

    expect(bucket).to include(
      source: :institution_activity,
      incoming: 100.to_d,
      outgoing: 40.to_d,
      net: 60.to_d,
      activity_count: 2
    )
    expect(bucket.fetch(:coverage)).to include(status: :complete)
  end

  it "falls back to budget-linked paid entries and keeps planned movement separate" do
    account = create(:account, user: user, kind: :checking)
    month = create(:budget_month, user: user, month_on: as_of.beginning_of_month, label: "July 2026")
    create(:account_snapshot, account: account, recorded_on: as_of.beginning_of_month, balance: 1_000)
    create(:expense_entry, user: user, budget_month: month, source_account: account, status: :paid, section: :income, occurred_on: as_of - 2.days, actual_amount: 500)
    create(:expense_entry, user: user, budget_month: month, source_account: account, status: :paid, section: :fixed, occurred_on: as_of - 1.day, actual_amount: 100)
    create(:expense_entry, user: user, budget_month: month, source_account: account, status: :planned, section: :fixed, occurred_on: as_of + 2.days, planned_amount: 75)

    bucket = described_class.new(account: account, as_of: as_of).call.fetch(:buckets).last

    expect(bucket).to include(
      source: :budget_entries,
      incoming: 500.to_d,
      outgoing: 100.to_d,
      net: 400.to_d,
      planned_outgoing: 75.to_d
    )
  end

  it "returns nil actuals instead of implying zero activity when no source exists" do
    account = create(:account, user: user, kind: :cash)

    bucket = described_class.new(account: account, as_of: as_of).call.fetch(:buckets).last

    expect(bucket).to include(source: :none, incoming: nil, outgoing: nil, net: nil)
  end

  it "marks incomplete import coverage as partial" do
    account = create(:account, user: user, kind: :credit_card)
    activity_import = create(
      :account_activity_import,
      account: account,
      started_on: as_of - 2.days,
      ended_on: as_of
    )
    create(:account_activity, account: account, account_activity_import: activity_import, transaction_on: as_of, account_delta: -25, amount: 25)

    bucket = described_class.new(account: account, as_of: as_of).call.fetch(:buckets).last

    expect(bucket.fetch(:coverage)).to include(status: :partial, starts_on: as_of - 2.days, ends_on: as_of)
    expect(bucket.fetch(:current_period)).to be(true)
  end

  it "uses positive display magnitudes for liability balances" do
    account = create(:account, user: user, kind: :credit_card)
    create(:account_snapshot, account: account, recorded_on: as_of.beginning_of_month, balance: -500)

    bucket = described_class.new(account: account, as_of: as_of).call.fetch(:buckets).last

    expect(bucket.fetch(:ending_balance)).to eq(500.to_d)
  end

  it "keeps chart movement totals equal to the exact institution drilldown rows" do
    account = create(:account, user: user, kind: :credit_card)
    activity_import = create(:account_activity_import, account: account, started_on: as_of.beginning_of_month, ended_on: as_of)
    create(:account_activity, account: account, account_activity_import: activity_import, transaction_on: as_of - 2.days, account_delta: -70, amount: 70)
    create(:account_activity, account: account, account_activity_import: activity_import, transaction_on: as_of - 1.day, account_delta: 25, amount: 25)

    bucket = described_class.new(account: account, as_of: as_of).call.fetch(:buckets).last
    outgoing = Accounts::ActivityLedgerQuery.new(
      account: account,
      filters: bucket.fetch(:drilldown).merge(direction: "outgoing")
    ).call.fetch(:institution_rows)
    incoming = Accounts::ActivityLedgerQuery.new(
      account: account,
      filters: bucket.fetch(:drilldown).merge(direction: "incoming")
    ).call.fetch(:institution_rows)

    expect(outgoing.sum { |row| row.account_delta.abs }).to eq(bucket.fetch(:outgoing))
    expect(incoming.sum { |row| row.account_delta.abs }).to eq(bucket.fetch(:incoming))
  end

  it "selects daily, weekly, monthly, and quarterly buckets from the requested range" do
    account = create(:account, user: user, kind: :checking)
    create(:account_snapshot, account: account, recorded_on: as_of - 30.months, balance: 100)

    expect(described_class.new(account: account, range: "30d", as_of: as_of).call.fetch(:bucket_unit)).to eq(:day)
    expect(described_class.new(account: account, range: "90d", as_of: as_of).call.fetch(:bucket_unit)).to eq(:week)
    expect(described_class.new(account: account, range: "12m", as_of: as_of).call.fetch(:bucket_unit)).to eq(:month)
    expect(described_class.new(account: account, range: "all", as_of: as_of).call.fetch(:bucket_unit)).to eq(:quarter)
    expect(described_class.new(account: account, range: "30d", as_of: as_of).call.fetch(:buckets).last.fetch(:current_period)).to be(true)
  end
end
