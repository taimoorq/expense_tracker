require "rails_helper"

RSpec.describe Identity::NewWorkspaceSetup do
  it "verifies a new workspace and makes its actual and planning ledger ready" do
    user = create(:user)
    workspace = described_class.call(user: user)

    expect(workspace).to have_attributes(target_reads_enabled: true, target_writes_enabled: true,
      target_backfill_version: Platform::TargetBackfill::WorkspaceBootstrap::VERSION)
    expect(workspace.target_backfilled_at).to be_present
    expect(workspace.migration_discrepancies.status_open).to be_empty
    expect(workspace.operation_runs.find_by!(operation_type: "target_model_backfill")).to be_state_succeeded
  end

  it "never upgrades an existing workspace, even an empty one" do
    user = create(:user)
    workspace = Identity::PersonalWorkspaceProvisioner.call(user: user).workspace

    expect { described_class.call(user: user) }.to raise_error(ArgumentError, /upgrade process/)
    expect(workspace.reload.target_reads_enabled?).to be(false)
  end

  it "refuses existing financial records without creating a workspace" do
    user = create(:user)
    create(:account, user: user)

    expect { described_class.call(user: user) }.to raise_error(ArgumentError, /upgrade process/)
    expect(BudgetWorkspace.where(legacy_owner_user: user)).to be_empty
  end
end
