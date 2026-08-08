require "rails_helper"

RSpec.describe "target budgeting commands" do
  it "creates a budget item idempotently" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)
    period = create(:budget_period, budget_workspace: workspace)
    attributes = {
      scheduled_on: Date.new(2026, 8, 12),
      flow_kind: "outflow",
      budget_group: "variable",
      planned_amount: 80,
      state: "open"
    }

    first = Budgeting::CreateBudgetItem.call(
      workspace: workspace,
      actor_membership: membership,
      budget_period: period,
      idempotency_key: "item-1",
      attributes: attributes
    )
    replay = Budgeting::CreateBudgetItem.call(
      workspace: workspace,
      actor_membership: membership,
      budget_period: period,
      idempotency_key: "item-1",
      attributes: attributes
    )

    expect(replay).to be_replayed
    expect(replay.value).to eq(first.value)
    expect(workspace.budget_items.count).to eq(1)
  end

  it "fulfills a plan with one atomic transaction, posting, allocation, and audit pair" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)
    account = create(:workspace_account, budget_workspace: workspace)
    item = create(:budget_item, budget_workspace: workspace, planned_amount: 60)

    result = Budgeting::FulfillItem.call(
      workspace: workspace,
      actor_membership: membership,
      budget_item: item,
      idempotency_key: "fulfill-1",
      transaction_attributes: { account: account, effective_on: Date.current, amount: 55 }
    )

    expect(result.value).to be_state_posted
    expect(result.value.account_postings.sole.amount).to eq(-55)
    expect(result.value.budget_allocations.sole).to have_attributes(budget_item: item, amount: 55)
    expect(workspace.audit_events.pluck(:action)).to contain_exactly("create", "match")
    expect(item.reload.remaining_amount).to eq(5)
  end

  it "rolls back every financial row if fulfillment cannot create its posting" do
    workspace = create(:budget_workspace)
    other_workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)
    foreign_account = create(:workspace_account, budget_workspace: other_workspace)
    item = create(:budget_item, budget_workspace: workspace)

    expect do
      Budgeting::FulfillItem.call(
        workspace: workspace,
        actor_membership: membership,
        budget_item: item,
        idempotency_key: "fulfill-invalid",
        transaction_attributes: { account: foreign_account, amount: 25 }
      )
    end.to raise_error(ArgumentError, "account must belong to the workspace and use its currency")

    expect(workspace.financial_transactions).to be_empty
    expect(workspace.budget_allocations).to be_empty
    expect(workspace.audit_events).to be_empty
    expect(workspace.operation_runs.find_by!(idempotency_key: "fulfill-invalid")).to be_state_failed
  end
end
