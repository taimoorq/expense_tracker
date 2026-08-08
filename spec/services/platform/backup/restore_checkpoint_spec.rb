require "rails_helper"

RSpec.describe "restore checkpoints" do
  let(:scopes) { Platform::Backup::V2::Preview::FINANCIAL_SCOPES + [ "preferences" ] }

  it "replaces a target workspace only after checkpointing and can auditably roll back" do
    current_user = create(:user)
    current_account = create(:account, user: current_user, name: "Original checking")
    current_month = create(:budget_month, user: current_user, month_on: Date.new(2026, 7, 1))
    create(
      :expense_entry,
      user: current_user,
      budget_month: current_month,
      source_account: current_account,
      payee: "Original rent",
      planned_amount: 900,
      actual_amount: 900,
      status: :paid,
      occurred_on: Date.new(2026, 7, 5)
    )
    current_workspace = Platform::TargetBackfill::Runner.call(user: current_user).workspace
    current_workspace.update!(target_writes_enabled: true, target_reads_enabled: true)

    source_user = create(:user)
    source_account = create(:account, user: source_user, name: "Restored checking")
    source_month = create(:budget_month, user: source_user, month_on: Date.new(2026, 8, 1))
    create(
      :expense_entry,
      user: source_user,
      budget_month: source_month,
      source_account: source_account,
      payee: "Restored rent",
      planned_amount: 1_200,
      actual_amount: 1_200,
      status: :paid,
      occurred_on: Date.new(2026, 8, 5)
    )
    source_workspace = Platform::TargetBackfill::Runner.call(user: source_user).workspace
    source_workspace.update!(target_writes_enabled: true, target_reads_enabled: true)
    payload = Platform::Backup::V2::Exporter.new(user: source_user, scopes: scopes).as_json

    result = Platform::UserDataImport.new(
      user: current_user,
      payload: payload,
      scopes: scopes,
      replace_existing: true
    ).call

    expect(result).to include(success: true, checkpoint_id: be_present)
    checkpoint = current_workspace.restore_checkpoints.find(result.fetch(:checkpoint_id))
    expect(checkpoint).to be_available
    expect(checkpoint.encrypted_payload).not_to include("Original checking", "Original rent")
    expect(current_user.accounts.reload.pluck(:name)).to eq([ "Restored checking" ])
    expect(current_user.expense_entries.reload.pluck(:payee)).to eq([ "Restored rent" ])
    expect(current_workspace.reload).to be_target_reads_enabled
    expect(current_workspace.data_transfer_runs.operation_restore.state_succeeded.order(:created_at).last.checkpoint_reference).to eq(checkpoint.id.to_s)

    rollback = Platform::Backup::RestoreCheckpointRollback.call(user: current_user, checkpoint: checkpoint)

    expect(rollback).to include(success: true)
    expect(current_user.accounts.reload.pluck(:name)).to eq([ "Original checking" ])
    expect(current_user.expense_entries.reload.pluck(:payee)).to eq([ "Original rent" ])
    expect(checkpoint.reload).to be_state_restored
    expect(current_workspace.reload).to be_target_reads_enabled
    expect(current_workspace.audit_events.where(action: "restore_checkpoint", entity_id: checkpoint.id)).to exist
    expect(current_workspace.audit_events.where(action: "restore_rollback", entity_id: checkpoint.id)).to exist
  end

  it "creates an encrypted checkpoint before a legacy replacement" do
    user = create(:user)
    create(:account, user: user, name: "Before")
    payload = Platform::UserDataExport.new(user: user, scopes: [ "accounts" ]).as_json.deep_dup
    payload[:data][:accounts].first[:name] = "After"

    result = Platform::UserDataImport.new(user: user, payload: payload, scopes: [ "accounts" ]).call

    expect(result).to include(success: true, checkpoint_id: be_present)
    checkpoint = user.reload.legacy_owned_budget_workspace.restore_checkpoints.find(result.fetch(:checkpoint_id))
    expect(checkpoint).to be_available
    expect(user.accounts.reload.pluck(:name)).to eq([ "After" ])
    expect(Platform::Backup::CheckpointCodec.decode(checkpoint.encrypted_payload).dig(:data, :accounts, 0, :name)).to eq("Before")
  end
end
