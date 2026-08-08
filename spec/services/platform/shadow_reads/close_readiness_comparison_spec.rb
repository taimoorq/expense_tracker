require "rails_helper"

RSpec.describe Platform::ShadowReads::CloseReadinessComparison do
  it "matches unresolved-source and unmatched-actual readiness counts" do
    user = create(:user)
    account = create(:account, user: user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    create(:account_snapshot, account: account, recorded_on: Date.new(2026, 8, 5), balance: 1_000)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace

    result = described_class.call(budget_month: month, period: workspace.budget_periods.sole)

    expect(result).to be_matched
    expect(result.target).to include(unmatched_count: 0, unresolved_account_count: 0)
  end

  it "stores only mismatched readiness field names" do
    user = create(:user)
    account = create(:account, user: user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    create(:account_snapshot, account: account, recorded_on: Date.new(2026, 8, 5), balance: 1_000)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.balance_observations.sole.update!(status: "disputed")

    result = described_class.call(budget_month: month, period: workspace.budget_periods.sole)

    expect(result).not_to be_matched
    discrepancy = workspace.migration_discrepancies.find_by!(code: "shadow_close_readiness_mismatch")
    expect(discrepancy.redacted_details.keys).to eq([ "mismatched_fields" ])
    expect(discrepancy.redacted_details.fetch("mismatched_fields")).to eq([ "unresolved_account_count" ])
    expect(discrepancy.redacted_details.to_json).not_to include("1000")
  end
end
