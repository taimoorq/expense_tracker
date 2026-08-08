require "rails_helper"

RSpec.describe Platform::TargetRelease::CanaryRehearsal do
  it "proves shadow parity, exercises target reads, and restores flags in order" do
    user = create(:user)
    account = create(:account, user: user, name: "Checking")
    create(:account_snapshot, account: account, balance: 2_400, recorded_on: Date.current.prev_day)
    create(:budget_month, user: user, month_on: Date.current.beginning_of_month)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace

    result = described_class.call(workspace: workspace, rehearsal_id: "canary-spec")

    expect(result).to be_passed
    expect(result.comparison_count).to be_positive
    expect(result.smoke_read_count).to eq(5)
    expect(workspace.reload).to have_attributes(
      target_writes_enabled: false,
      target_reads_enabled: false
    )
    expect(result.operation_run).to be_state_succeeded
    expect(result.operation_run).to have_attributes(
      progress_current: 4,
      progress_total: 4,
      progress_label: "Rollback verified"
    )
    expect(workspace.audit_events.where(action: "access_change", operation_run: result.operation_run)).to exist
  end

  it "fails durably without changing flags when a discrepancy is open" do
    user = create(:user)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.migration_discrepancies.create!(
      legacy_record_type: "User",
      legacy_record_id: user.id,
      code: "canary_spec_block",
      status: "open",
      redacted_details: { "kind" => "spec" }
    )

    expect do
      described_class.call(workspace: workspace, rehearsal_id: "blocked-canary-spec")
    end.to raise_error(described_class::GateFailed, "Open migration discrepancies block target reads.")

    expect(workspace.reload).to have_attributes(
      target_writes_enabled: false,
      target_reads_enabled: false
    )
    expect(workspace.operation_runs.find_by!(operation_type: "target_read_canary_rehearsal")).to be_state_failed
  end
end
