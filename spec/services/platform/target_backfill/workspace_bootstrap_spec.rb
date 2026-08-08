require "rails_helper"

RSpec.describe Platform::TargetBackfill::WorkspaceBootstrap do
  it "creates one owner workspace and assigns every legacy ownership bridge" do
    user = create(:user)
    account = create(:account, user: user)
    month = create(:budget_month, user: user)
    entry = create(:expense_entry, user: user, budget_month: month)
    schedule = create(:pay_schedule, user: user)

    result = described_class.call(user: user)

    expect(result.workspace.legacy_owner_user).to eq(user)
    expect(result.membership).to be_role_owner
    expect(result.membership).to be_status_active
    expect(account.reload).to have_attributes(
      budget_workspace_id: result.workspace.id,
      currency_code: "USD"
    )
    expect(month.reload.budget_workspace_id).to eq(result.workspace.id)
    expect(entry.reload.budget_workspace_id).to eq(result.workspace.id)
    expect(schedule.reload.budget_workspace_id).to eq(result.workspace.id)
    expect(result.operation_run).to be_state_running
  end

  it "is resumable and does not duplicate identity records" do
    user = create(:user)
    create(:account, user: user)

    first = described_class.call(user: user)
    replay = described_class.call(user: user)

    expect(replay.workspace).to eq(first.workspace)
    expect(replay.membership).to eq(first.membership)
    expect(replay.operation_run).to eq(first.operation_run)
    expect(replay.assigned_counts.values.sum).to eq(0)
    expect(BudgetWorkspace.where(legacy_owner_user: user).count).to eq(1)
  end

  it "stops before assignment when an account uses another currency" do
    user = create(:user)
    account = create(:account, user: user, currency_code: "EUR")

    expect { described_class.call(user: user) }
      .to raise_error(described_class::CurrencyMismatch, "1 accounts use another currency")
    expect(account.reload.budget_workspace_id).to be_nil
    expect(BudgetWorkspace.where(legacy_owner_user: user)).to be_empty
  end
end
