require "rails_helper"

RSpec.describe Budgeting::CreatePeriod do
  it "normalizes the start date and returns an existing period without duplicating it" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)

    first = described_class.call(
      workspace: workspace,
      actor_membership: membership,
      starts_on: Date.new(2026, 8, 17),
      idempotency_key: "period-august"
    )
    second = described_class.call(
      workspace: workspace,
      actor_membership: membership,
      starts_on: Date.new(2026, 8, 1),
      idempotency_key: "period-august-another-client"
    )

    expect(first.value.starts_on).to eq(Date.new(2026, 8, 1))
    expect(second.value).to eq(first.value)
    expect(workspace.budget_periods.count).to eq(1)
    expect(workspace.audit_events.where(entity_type: "BudgetPeriod", entity_id: first.value.id).count).to eq(1)
  end
end
