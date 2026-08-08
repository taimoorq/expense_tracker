require "rails_helper"

RSpec.describe "target account reconciliation commands" do
  it "matches partial actuals without allowing aggregate overallocation" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)
    transaction = create(:financial_transaction, budget_workspace: workspace, gross_amount: 100)
    first_item = create(:budget_item, budget_workspace: workspace)
    second_item = create(:budget_item, budget_workspace: workspace)

    first = Accounts::MatchTransaction.call(
      workspace: workspace,
      actor_membership: membership,
      transaction: transaction,
      budget_item: first_item,
      amount: 60,
      idempotency_key: "match-1"
    )
    replay = Accounts::MatchTransaction.call(
      workspace: workspace,
      actor_membership: membership,
      transaction: transaction,
      budget_item: first_item,
      amount: 60,
      idempotency_key: "match-1"
    )

    expect(replay).to be_replayed
    expect(first.value.amount).to eq(60)
    expect(transaction.reload.available_to_allocate).to eq(40)
    expect do
      Accounts::MatchTransaction.call(
        workspace: workspace,
        actor_membership: membership,
        transaction: transaction,
        budget_item: second_item,
        amount: 41,
        idempotency_key: "match-too-large"
      )
    end.to raise_error(Accounts::MatchTransaction::InvalidMatch, "allocation exceeds the transaction amount available")
    expect(transaction.reload.budget_allocations.sum(:amount)).to eq(60)
  end

  it "unmatches once and retains append-only evidence" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)
    allocation = create(:budget_allocation, budget_workspace: workspace)
    item = allocation.budget_item

    first = Accounts::UnmatchTransaction.call(
      workspace: workspace,
      actor_membership: membership,
      allocation: allocation,
      idempotency_key: "unmatch-1"
    )
    replay = Accounts::UnmatchTransaction.call(
      workspace: workspace,
      actor_membership: membership,
      allocation: allocation,
      idempotency_key: "unmatch-1"
    )

    expect(first.value).to eq(item)
    expect(replay).to be_replayed
    expect(BudgetAllocation.where(id: allocation.id)).to be_empty
    expect(workspace.audit_events.where(action: "unmatch", entity_id: allocation.id).count).to eq(1)
  end

  it "records a trusted balance observation idempotently" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)
    account = create(:workspace_account, budget_workspace: workspace)
    timestamp = Time.current.change(usec: 0)
    attributes = {
      observed_at: timestamp,
      effective_through_at: timestamp,
      balance: 1_250,
      available_balance: 1_200
    }

    first = Accounts::RecordBalanceObservation.call(
      workspace: workspace,
      actor_membership: membership,
      account: account,
      idempotency_key: "observation-1",
      attributes: attributes
    )
    replay = Accounts::RecordBalanceObservation.call(
      workspace: workspace,
      actor_membership: membership,
      account: account,
      idempotency_key: "observation-1",
      attributes: attributes
    )

    expect(replay).to be_replayed
    expect(replay.value).to eq(first.value)
    expect(first.value).to be_status_trusted
    expect(account.balance_observations.count).to eq(1)
  end

  it "requires reopening before late activity can change a closed month match" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)
    period = create(:budget_period, budget_workspace: workspace, state: "closed")
    item = create(:budget_item, budget_workspace: workspace, budget_period: period)
    transaction = create(:financial_transaction, budget_workspace: workspace)

    expect do
      Accounts::MatchTransaction.call(
        workspace: workspace,
        actor_membership: membership,
        transaction: transaction,
        budget_item: item,
        amount: 25,
        idempotency_key: "late-closed-match"
      )
    end.to raise_error(Accounts::MatchTransaction::InvalidMatch, /Reopen the closed month/)

    expect(workspace.budget_allocations).to be_empty
  end
end
