require "rails_helper"

RSpec.describe "target budget period lifecycle" do
  it "closes and reopens with immutable calculation evidence and idempotent operations" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)
    period = create(:budget_period, budget_workspace: workspace)
    create(:budget_item, budget_workspace: workspace, budget_period: period, planned_amount: 100)

    first_close = Budgeting::ClosePeriod.call(
      workspace: workspace,
      actor_membership: membership,
      budget_period: period,
      idempotency_key: "close-1"
    )
    close_replay = Budgeting::ClosePeriod.call(
      workspace: workspace,
      actor_membership: membership,
      budget_period: period,
      idempotency_key: "close-1"
    )

    expect(close_replay).to be_replayed
    expect(first_close.value.calculation_input_digest).to match(/\A[0-9a-f]{64}\z/)
    expect(period.reload).to be_state_closed
    expect do
      Budgeting::CreateBudgetItem.call(
        workspace: workspace,
        actor_membership: membership,
        budget_period: period,
        idempotency_key: "closed-item",
        attributes: { flow_kind: "outflow", budget_group: "other", planned_amount: 10 }
      )
    end.to raise_error(ArgumentError, "budget period must be open in this workspace")

    reopened = Budgeting::ReopenPeriod.call(
      workspace: workspace,
      actor_membership: membership,
      budget_period: period,
      idempotency_key: "reopen-1"
    )

    expect(reopened.value).to be_state_reopened
    expect(first_close.value.reload).to be_state_superseded
    expect(workspace.audit_events.pluck(:action)).to contain_exactly("close", "reopen")
  end

  it "uses one as-of readiness result for preview and the frozen close evidence" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)
    period = create(:budget_period, budget_workspace: workspace, starts_on: Date.new(2026, 8, 1))
    trusted_account = create(:workspace_account, budget_workspace: workspace)
    create(:workspace_account, budget_workspace: workspace)
    create(
      :balance_observation,
      budget_workspace: workspace,
      account: trusted_account,
      effective_through_at: Date.new(2026, 8, 10).end_of_day,
      observed_at: Date.new(2026, 8, 10).end_of_day
    )
    create(:financial_transaction, budget_workspace: workspace, effective_on: Date.new(2026, 8, 12), state: "posted")

    readiness = Budgeting::CloseReadiness.call(period: period)
    close = Budgeting::ClosePeriod.call(
      workspace: workspace,
      actor_membership: membership,
      budget_period: period,
      idempotency_key: "close-with-readiness"
    ).value

    expect(readiness).to have_attributes(
      unmatched_count: 1,
      unresolved_account_count: 1,
      issue_count: 2,
      ready?: false,
      calculation_version: "target-v1"
    )
    expect(close).to have_attributes(unmatched_count: 1, unresolved_count: 1)
  end
end
