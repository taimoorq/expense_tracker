require "rails_helper"

RSpec.describe Platform::ShadowReads::AttentionComparison do
  it "matches common target attention semantics and records no financial values" do
    user = create(:user)
    account = create(:account, user: user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      occurred_on: Date.new(2026, 8, 5),
      category: "Utilities",
      payee: "Power",
      planned_amount: 75,
      status: :planned
    )
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    period = workspace.budget_periods.sole

    result = described_class.call(
      budget_month: month,
      period: period,
      as_of: Date.new(2026, 8, 7)
    )

    expect(result).to be_matched
    expect(workspace.migration_discrepancies.where(code: "shadow_attention_summary_mismatch")).to be_empty
  end

  it "persists only the comparison date and mismatched field names" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    entry = create(
      :expense_entry,
      user: user,
      budget_month: month,
      occurred_on: Date.new(2026, 8, 5),
      category: "Utilities",
      payee: "Power",
      planned_amount: 75,
      status: :planned
    )
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.budget_items.sole.update!(scheduled_on: Date.new(2026, 8, 20))

    result = described_class.call(
      budget_month: month,
      period: workspace.budget_periods.sole,
      as_of: Date.new(2026, 8, 7)
    )

    expect(result).not_to be_matched
    discrepancy = workspace.migration_discrepancies.find_by!(code: "shadow_attention_summary_mismatch")
    expect(discrepancy.redacted_details.keys).to contain_exactly("as_of", "mismatched_fields")
    expect(discrepancy.redacted_details.fetch("mismatched_fields")).to include("due_planned_count")
    expect(discrepancy.redacted_details.to_json).not_to include(entry.payee, "75")
  end
end
