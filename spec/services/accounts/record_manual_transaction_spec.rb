require "rails_helper"

RSpec.describe Accounts::RecordManualTransaction do
  it "records and replays a posted outflow with one signed posting" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)
    account = create(:workspace_account, budget_workspace: workspace)
    attributes = {
      effective_on: Date.new(2026, 8, 7),
      description: "Household purchase",
      amount: 25,
      flow_kind: "outflow",
      account: account
    }

    first = described_class.call(
      workspace: workspace,
      actor_membership: membership,
      idempotency_key: "manual-outflow-1",
      attributes: attributes
    )
    replay = described_class.call(
      workspace: workspace,
      actor_membership: membership,
      idempotency_key: "manual-outflow-1",
      attributes: attributes
    )

    expect(first.value.account_postings.sole.amount).to eq(-25)
    expect(replay).to be_replayed
    expect(replay.value).to eq(first.value)
    expect(workspace.financial_transactions.count).to eq(1)
    expect(workspace.audit_events.count).to eq(1)
  end

  it "records transfers as equal-and-opposite postings" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)
    source = create(:workspace_account, budget_workspace: workspace)
    destination = create(:workspace_account, budget_workspace: workspace)

    result = described_class.call(
      workspace: workspace,
      actor_membership: membership,
      idempotency_key: "transfer-1",
      attributes: {
        effective_on: Date.current,
        description: "Move to savings",
        amount: 100,
        flow_kind: "transfer",
        source_account: source,
        destination_account: destination
      }
    )

    expect(result.value.account_postings.order(:sequence_number).pluck(:amount)).to eq([ -100, 100 ])
  end

  it "does not let a viewer create financial data" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace, role: "viewer")
    account = create(:workspace_account, budget_workspace: workspace)

    expect do
      described_class.call(
        workspace: workspace,
        actor_membership: membership,
        idempotency_key: "viewer-write",
        attributes: {
          effective_on: Date.current,
          description: "Blocked",
          amount: 10,
          flow_kind: "outflow",
          account: account
        }
      )
    end.to raise_error(Identity::WorkspaceAccess::NotAuthorized)
    expect(workspace.financial_transactions).to be_empty
  end
end
