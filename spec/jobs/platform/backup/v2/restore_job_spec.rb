require "rails_helper"
require "active_job/continuation/test_helper"

RSpec.describe Platform::Backup::V2::RestoreJob, type: :job do
  include ActiveJob::Continuation::TestHelper

  let(:scopes) { Platform::Backup::V2::Preview::FINANCIAL_SCOPES }

  def payload_with_account(name: "Restored checking")
    source = create(:user)
    create(:account, user: source, name: name)
    Platform::TargetBackfill::Runner.call(user: source)
    Platform::Backup::V2::Exporter.new(user: source, scopes: scopes).as_json
  end

  def stage(payload:, destination:, replace_existing: false)
    token = Platform::BackupRestorePreviewStore.new(user: destination).store(
      payload: payload,
      scopes: scopes,
      encrypted: false
    )
    draft = Platform::BackupRestorePreviewStore.new(user: destination).load_draft(token)
    operation = Platform::Backup::V2::Dispatch.call(
      draft: draft,
      replace_existing: replace_existing
    )
    clear_enqueued_jobs
    [ draft.reload, operation ]
  end

  it "activates a verified stage atomically and replays without duplicate records" do
    destination = create(:user)
    draft, operation = stage(payload: payload_with_account, destination: destination)

    described_class.perform_now(operation.id, draft.id)
    described_class.perform_now(operation.id, draft.id)

    expect(operation.reload).to have_attributes(state: "succeeded", progress_current: 4, progress_total: 4)
    expect(draft.reload).to be_state_consumed
    expect(draft.encrypted_payload).to be_empty
    expect(draft.data_transfer_run.reload).to be_state_succeeded
    expect(destination.accounts.reload.pluck(:name)).to eq([ "Restored checking" ])
  end

  it "resumes after a worker stops before activation" do
    destination = create(:user)
    draft, operation = stage(payload: payload_with_account, destination: destination)
    described_class.perform_later(operation.id, draft.id)

    interrupt_job_after_step(described_class, :validate_stage) do
      perform_enqueued_jobs(only: described_class)
    end

    expect(destination.accounts).to be_empty
    expect(operation.reload).to be_state_pending

    perform_enqueued_jobs(only: described_class)

    expect(operation.reload).to be_state_succeeded
    expect(destination.accounts.reload.pluck(:name)).to eq([ "Restored checking" ])
  end

  it "creates an encrypted checkpoint before replacing existing financial data" do
    destination = create(:user)
    create(:account, user: destination, name: "Before checking")
    workspace = Platform::TargetBackfill::Runner.call(user: destination).workspace
    workspace.update!(target_writes_enabled: true, target_reads_enabled: true)
    draft, operation = stage(
      payload: payload_with_account(name: "After checking"),
      destination: destination,
      replace_existing: true
    )

    described_class.perform_now(operation.id, draft.id)

    checkpoint = draft.reload.restore_checkpoint
    expect(checkpoint).to be_available
    expect(checkpoint.encrypted_payload).not_to include("Before checking")
    expect(draft.data_transfer_run.reload.checkpoint_reference).to eq(checkpoint.id)
    expect(destination.accounts.reload.pluck(:name)).to eq([ "After checking" ])
  end

  it "rolls replacement cleanup back when compatibility activation fails" do
    destination = create(:user)
    create(:account, user: destination, name: "Keep checking")
    workspace = Platform::TargetBackfill::Runner.call(user: destination).workspace
    workspace.update!(target_writes_enabled: true, target_reads_enabled: true)
    draft, operation = stage(
      payload: payload_with_account(name: "Rejected checking"),
      destination: destination,
      replace_existing: true
    )
    allow_any_instance_of(Platform::Backup::V2::LegacyProjection).to receive(:call).and_raise(
      Platform::Backup::V2::LegacyProjection::ProjectionError,
      "forced activation failure"
    )

    described_class.perform_now(operation.id, draft.id)

    expect(destination.accounts.reload.pluck(:name)).to eq([ "Keep checking" ])
    expect(operation.reload).to be_state_failed
    expect(draft.reload).to be_state_queued
    expect(draft.data_transfer_run.reload).to be_state_pending
    expect(enqueued_jobs).to include(include(job: described_class))
  end

  it "shares the workspace mutation concurrency group with account imports" do
    destination = create(:user)
    draft, operation = stage(payload: payload_with_account, destination: destination)

    restore_key = described_class.new(operation.id, draft.id).concurrency_key

    expect(restore_key).to eq("workspace_mutations/#{operation.budget_workspace_id}")
    expect(described_class.concurrency_group).to eq(Accounts::ActivityImports::CommitJob.concurrency_group)
  end
end
