require "rails_helper"

RSpec.describe Platform::TargetRelease::Cutover do
  it "enables an eligible cohort idempotently and rolls reads back while preserving writes" do
    user = create(:user)
    account = create(:account, user: user)
    create(:account_snapshot, account: account, balance: 2_400, recorded_on: Date.current.prev_day)
    create(:budget_month, user: user, month_on: Date.current.beginning_of_month)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    membership = workspace.workspace_memberships.find_by!(user: user)

    enabled = described_class.call(
      workspace: workspace,
      actor_membership: membership,
      action: "enable",
      change_id: "deploy-2026-08-07"
    )
    replay = described_class.call(
      workspace: workspace,
      actor_membership: membership,
      action: "enable",
      change_id: "deploy-2026-08-07"
    )

    expect(enabled.workspace).to have_attributes(target_writes_enabled: true, target_reads_enabled: true)
    expect(enabled.comparison_count).to be_positive
    expect(replay.operation_run).to eq(enabled.operation_run)
    expect(workspace.audit_events.where(action: "access_change", operation_run: enabled.operation_run).count).to eq(1)

    rolled_back = described_class.call(
      workspace: workspace,
      actor_membership: membership,
      action: "rollback",
      change_id: "rollback-2026-08-07"
    )

    expect(rolled_back.workspace).to have_attributes(target_writes_enabled: true, target_reads_enabled: false)
    expect(rolled_back.comparison_count).to eq(0)
    expect(workspace.audit_events.where(action: "access_change", operation_run: rolled_back.operation_run)).to exist
  end

  it "refuses enablement when an open discrepancy exists but always permits read rollback" do
    user = create(:user)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    membership = workspace.workspace_memberships.find_by!(user: user)
    workspace.migration_discrepancies.create!(
      legacy_record_type: "User",
      legacy_record_id: user.id,
      code: "cutover_spec_block",
      status: "open",
      redacted_details: { "kind" => "spec" }
    )

    expect do
      described_class.call(
        workspace: workspace,
        actor_membership: membership,
        action: "enable",
        change_id: "blocked-deploy"
      )
    end.to raise_error(Platform::TargetRelease::Eligibility::GateFailed)

    workspace.update!(target_writes_enabled: true, target_reads_enabled: true)
    result = described_class.call(
      workspace: workspace,
      actor_membership: membership,
      action: "rollback",
      change_id: "emergency-rollback"
    )

    expect(result.workspace).to have_attributes(target_writes_enabled: true, target_reads_enabled: false)
  end
end
