require "rails_helper"

RSpec.describe Accounts::TargetNetWorthTrend do
  it "breaks the series instead of treating an account without a source as zero" do
    user = create(:user)
    first = create(:account, user: user, kind: :checking)
    second = create(:account, user: user, kind: :checking)
    create(:account_snapshot, account: first, recorded_on: Date.new(2026, 1, 1), balance: 1_000)
    create(:account_snapshot, account: second, recorded_on: Date.new(2026, 2, 1), balance: 500)
    Platform::TargetBackfill::Runner.call(user: user)

    rows = described_class.call(accounts: [ first.reload, second.reload ], as_of: Date.new(2026, 3, 1))

    expect(rows.first).to include(date: Date.new(2026, 1, 1), value: nil, coverage_count: 1, account_count: 2, complete: false)
    expect(rows.second).to include(date: Date.new(2026, 2, 1), value: 1_500.0, coverage_count: 2, account_count: 2, complete: true)
    expect(rows.last).to include(date: Date.new(2026, 3, 1), value: 1_500.0, complete: true)
  end
end
