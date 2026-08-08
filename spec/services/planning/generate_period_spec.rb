require "rails_helper"

RSpec.describe Planning::GeneratePeriod do
  it "materializes recurring identities and items exactly once across operation keys" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)
    account = create(:workspace_account, budget_workspace: workspace)
    period = create(:budget_period, budget_workspace: workspace, starts_on: Date.new(2026, 8, 1))
    template = create(
      :planning_template,
      budget_workspace: workspace,
      name: "Internet",
      default_amount: 75,
      source_account: account
    )
    RecurrenceRule.create!(
      planning_template: template,
      cadence: "monthly",
      interval_count: 1,
      anchor_on: Date.new(2026, 1, 12),
      day_one: 12,
      weekend_policy: "none",
      starts_on: Date.new(2026, 1, 1)
    )

    first = described_class.call(
      workspace: workspace,
      actor_membership: membership,
      budget_period: period,
      idempotency_key: "generate-august"
    )
    replay = described_class.call(
      workspace: workspace,
      actor_membership: membership,
      budget_period: period,
      idempotency_key: "generate-august"
    )
    another_client = described_class.call(
      workspace: workspace,
      actor_membership: membership,
      budget_period: period,
      idempotency_key: "generate-august-another-client"
    )

    occurrence = workspace.recurring_occurrences.sole
    expect(occurrence).to be_state_materialized
    expect(occurrence.budget_item).to have_attributes(planned_amount: 75, intended_source_account: account)
    expect(replay).to be_replayed
    expect(another_client.operation_run.result_counts).to eq("occurrences" => 0, "budget_items" => 0)
    expect(workspace.recurring_occurrences.count).to eq(1)
    expect(workspace.budget_items.count).to eq(1)
    expect(workspace.audit_events.where(action: "generate").count).to eq(1)
    expect(first.value).to eq(period)
  end

  it "caps payment-plan generation at the derived amount remaining" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)
    period = create(:budget_period, budget_workspace: workspace)
    template = create(
      :planning_template,
      budget_workspace: workspace,
      kind: "payment_plan",
      budget_group: "debt",
      default_amount: 25
    )
    RecurrenceRule.create!(
      planning_template: template,
      cadence: "monthly",
      interval_count: 1,
      anchor_on: Date.new(2026, 1, 10),
      day_one: 10,
      weekend_policy: "none",
      starts_on: Date.new(2026, 1, 1)
    )
    PaymentPlanTerm.create!(
      planning_template: template,
      total_due: 100,
      opening_paid_adjustment: 90,
      monthly_target: 25
    )

    described_class.call(
      workspace: workspace,
      actor_membership: membership,
      budget_period: period,
      idempotency_key: "payment-plan-generation"
    )

    expect(workspace.budget_items.sole.planned_amount).to eq(10)
  end
end
