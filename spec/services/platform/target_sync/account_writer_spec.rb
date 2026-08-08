require "rails_helper"

RSpec.describe Platform::TargetSync::AccountWriter do
  it "maps account creation and its opening observation in the same transaction" do
    user = create(:user)
    result = Platform::TargetBackfill::Runner.call(user: user)
    workspace = result.workspace
    workspace.update!(target_writes_enabled: true)

    creation = Accounts::Creator.call(
      user: user,
      account_params: { name: "Savings", kind: "savings", active: true },
      initial_snapshot_params: { recorded_on: Date.new(2026, 8, 1), balance: 500 },
      credit_card_payment_schedule_params: {}
    )

    expect(creation).to be_success
    expect(creation.account).to have_attributes(budget_workspace: workspace, currency_code: "USD")
    expect(
      workspace.legacy_record_mappings.find_by!(
        legacy_record_type: "Account",
        legacy_record_id: creation.account.id,
        target_record_type: "Account"
      ).target_record_id
    ).to eq(creation.account.id)
    expect(workspace.balance_observations.sole.balance).to eq(500.to_d)
  end

  it "records account edits and archival through the target operation boundary" do
    user = create(:user)
    account = create(:account, user: user)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.update!(target_writes_enabled: true)
    account.reload

    expect(Accounts::Updater.call(account: account, attributes: { active: false })).to be(true)

    operation = workspace.operation_runs.find_by!(operation_type: "sync_legacy_account")
    expect(operation).to be_state_succeeded
    expect(operation.audit_events.sole.action).to eq("archive")
  end
end
