require "rails_helper"

RSpec.describe Platform::ShadowReads::RecurrenceCoverageComparison do
  it "verifies mapped occurrence identity, schedule, template, period, and materialization" do
    user = create(:user)
    template = create(:monthly_bill, user: user, name: "Utilities")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    entry = create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_template: template,
      source_file: "monthly_bill",
      generated_entry_key: "monthly_bill:#{template.id}:2026-08-10",
      occurred_on: Date.new(2026, 8, 10),
      category: "Utilities",
      payee: "Utilities",
      planned_amount: 100
    )
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    period = workspace.budget_periods.sole

    result = described_class.call(budget_month: month, period: period)

    expect(result).to be_matched
    expect(result.target).to include(occurrence_count: 1, orphan_target_count: 0)
    expect(entry).to be_persisted
  end

  it "persists only mismatched relationship field names" do
    user = create(:user)
    template = create(:monthly_bill, user: user, name: "Utilities")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_template: template,
      source_file: "monthly_bill",
      generated_entry_key: "monthly_bill:#{template.id}:2026-08-10",
      occurred_on: Date.new(2026, 8, 10),
      category: "Utilities",
      payee: "Utilities",
      planned_amount: 100
    )
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    occurrence = workspace.recurring_occurrences.sole
    occurrence.update!(scheduled_on: Date.new(2026, 8, 11))

    result = described_class.call(budget_month: month, period: workspace.budget_periods.sole)

    expect(result).not_to be_matched
    discrepancy = workspace.migration_discrepancies.find_by!(code: "shadow_recurrence_coverage_mismatch")
    expect(discrepancy.redacted_details.keys).to eq([ "mismatched_fields" ])
    expect(discrepancy.redacted_details.fetch("mismatched_fields")).to include("wrong_date_count")
    expect(discrepancy.redacted_details.to_json).not_to include("Utilities", "100")
  end
end
