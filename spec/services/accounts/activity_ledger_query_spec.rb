require "rails_helper"

RSpec.describe Accounts::ActivityLedgerQuery do
  let(:user) { create(:user) }
  let(:account) { create(:account, user: user, kind: :checking) }
  let(:month) { create(:budget_month, user: user, month_on: Date.new(2026, 7, 1), label: "July 2026") }
  let(:activity_import) { create(:account_activity_import, account: account) }

  before do
    create(:account_activity, account: account, account_activity_import: activity_import, transaction_on: Date.new(2026, 7, 3), account_delta: -40, amount: 40)
    create(:account_activity, account: account, account_activity_import: activity_import, transaction_on: Date.new(2026, 7, 4), account_delta: 100, amount: 100)
    create(:expense_entry, user: user, budget_month: month, source_account: account, occurred_on: Date.new(2026, 7, 5), status: :paid, section: :fixed, actual_amount: 25)
    create(:expense_entry, user: user, budget_month: month, source_account: account, occurred_on: Date.new(2026, 7, 6), status: :paid, section: :income, actual_amount: 75)
  end

  it "keeps institution activity and budget-linked entries in separate result sets" do
    result = described_class.new(account: account).call

    expect(result.fetch(:institution_rows).size).to eq(2)
    expect(result.fetch(:budget_entries).size).to eq(2)
    expect(result.fetch(:institution_net)).to eq(60.to_d)
    expect(result.fetch(:budget_net)).to eq(50.to_d)
  end

  it "only preloads associations used by the full ledger" do
    preview = described_class.new(account: account).call
    preview_activity = preview.fetch(:institution_rows).first
    preview_entry = preview.fetch(:budget_entries).first

    expect(preview_activity.association(:account_activity_import)).not_to be_loaded
    expect(preview_entry.association(:budget_month)).not_to be_loaded

    ledger = described_class.new(account: account, preload_ledger_associations: true).call
    ledger_activity = ledger.fetch(:institution_rows).first
    ledger_entry = ledger.fetch(:budget_entries).first

    expect(ledger_activity.association(:account_activity_import)).to be_loaded
    expect(ledger_entry.association(:budget_month)).to be_loaded
    expect(ledger_entry.association(:source_account)).not_to be_loaded
    expect(ledger_entry.association(:destination_account)).not_to be_loaded
    expect(ledger_entry.association(:source_template)).not_to be_loaded
  end

  it "filters by source, direction, and exact dates" do
    result = described_class.new(
      account: account,
      filters: {
        source: "institution_activity",
        direction: "outgoing",
        starts_on: "2026-07-03",
        ends_on: "2026-07-03"
      }
    ).call

    expect(result.fetch(:institution_rows).map(&:account_delta)).to eq([ -40.to_d ])
    expect(result.fetch(:budget_entries)).to be_empty
  end

  it "ignores invalid filters instead of widening into another user's data" do
    other_account = create(:account)
    other_import = create(:account_activity_import, account: other_account)
    create(:account_activity, account: other_account, account_activity_import: other_import, account_delta: -999, amount: 999)

    result = described_class.new(
      account: account,
      filters: { source: "unknown", direction: "unknown", starts_on: "not-a-date" }
    ).call

    expect(result.fetch(:institution_rows)).to all(have_attributes(account_id: account.id))
    expect(result.fetch(:budget_entries)).to all(have_attributes(user_id: user.id))
  end

  it "reproduces merchant and classification insight drilldowns" do
    create(:account_activity, account: account, account_activity_import: activity_import, transaction_on: Date.new(2026, 7, 7), description: "SQ *CLOUD HOST 123456", category: "Fees", activity_type: "Fee", account_delta: -15, amount: 15)

    merchant_result = described_class.new(
      account: account,
      filters: { source: "institution_activity", merchant: "CLOUD HOST" }
    ).call
    fee_result = described_class.new(
      account: account,
      filters: { source: "institution_activity", classification: "fee" }
    ).call

    expect(merchant_result.fetch(:institution_rows).map(&:description)).to contain_exactly("SQ *CLOUD HOST 123456")
    expect(fee_result.fetch(:institution_rows).map(&:description)).to include("SQ *CLOUD HOST 123456")
    expect(fee_result.fetch(:institution_rows)).to all(satisfy { |row| Accounts::ActivityInsights::Classifier.call(row) == :fee })
  end
end
