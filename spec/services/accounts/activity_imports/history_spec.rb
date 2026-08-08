require "rails_helper"

RSpec.describe Accounts::ActivityImports::History do
  it "returns a bounded newest-first log and recommends reimporting the last covered day" do
    user = create(:user)
    account = create(:account, user: user)
    older = create(
      :account_activity_import,
      account: account,
      started_on: Date.new(2026, 5, 1),
      ended_on: Date.new(2026, 5, 31),
      created_at: Time.zone.local(2026, 6, 1, 9)
    )
    latest = create(
      :account_activity_import,
      account: account,
      started_on: Date.new(2026, 6, 1),
      ended_on: Date.new(2026, 6, 30),
      created_at: Time.zone.local(2026, 7, 1, 10, 30)
    )

    result = described_class.call(
      account: account,
      candidate_starts_on: Date.new(2026, 6, 30),
      candidate_ends_on: Date.new(2026, 7, 31),
      limit: 1
    )

    expect(result.imports).to eq([ latest ])
    expect(result.latest_import).to eq(latest)
    expect(result.recommended_start_on).to eq(Date.new(2026, 6, 30))
    expect(result.overlap_count).to eq(1)
    expect(result).to be_overlap
    expect(result).to be_limited
    expect(older.imported_at).to eq(older.created_at)
  end

  it "returns an empty, usable log for an account with no imports" do
    account = create(:account)

    result = described_class.call(account: account)

    expect(result.imports).to be_empty
    expect(result.latest_import).to be_nil
    expect(result.recommended_start_on).to be_nil
    expect(result).not_to be_overlap
    expect(result).not_to be_limited
  end
end
