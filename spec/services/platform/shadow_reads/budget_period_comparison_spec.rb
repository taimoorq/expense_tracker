require "rails_helper"

RSpec.describe Platform::ShadowReads::BudgetPeriodComparison do
  it "matches planned, actual, remaining, forecast, variance, and unmatched totals exactly" do
    user = create(:user)
    account = create(:account, user: user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      occurred_on: Date.new(2026, 8, 4),
      section: :income,
      planned_amount: 1_000,
      actual_amount: 1_000,
      status: :paid
    )
    create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      occurred_on: Date.new(2026, 8, 8),
      section: :fixed,
      planned_amount: 500,
      status: :planned
    )
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    period = workspace.budget_periods.sole

    result = described_class.call(budget_month: month, period: period)

    expect(result).to be_matched
    expect(result.target).to have_attributes(
      planned_income: 1_000.to_d,
      planned_outflow: 500.to_d,
      actual_income: 1_000.to_d,
      actual_outflow: 0.to_d,
      remaining_outflow: 500.to_d,
      forecast_net: 500.to_d
    )
  end

  it "records only mismatched field names" do
    user = create(:user)
    month = create(:budget_month, user: user)
    create(:expense_entry, user: user, budget_month: month, planned_amount: 50)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.budget_items.sole.update!(planned_amount: 49)

    result = described_class.call(budget_month: month, period: workspace.budget_periods.sole)

    expect(result).not_to be_matched
    discrepancy = workspace.migration_discrepancies.find_by!(code: "shadow_budget_period_summary_mismatch")
    expect(discrepancy.redacted_details.keys).to eq([ "mismatched_fields" ])
    expect(discrepancy.redacted_details.to_json).not_to include("49", "50")
  end
end
