require "rails_helper"

RSpec.describe Accounts::ActivityImports::Dispatch do
  include ActiveJob::TestHelper

  it "persists a pending operation before enqueueing identifier-only arguments" do
    draft = create(:account_activity_import_draft)
    create(:workspace_membership, budget_workspace: draft.budget_workspace, user: draft.user)

    operation = nil
    expect do
      operation = described_class.call(draft: draft)
    end.to have_enqueued_job(Accounts::ActivityImports::CommitJob)

    expect(operation).to have_attributes(
      state: "pending",
      job_class: "Accounts::ActivityImports::CommitJob",
      job_arguments: [ draft.id ]
    )
    expect(operation.enqueued_at).to be_present
    expect(draft.reload).to have_attributes(state: "queued", operation_run: operation)
  end

  it "reuses the same operation and enqueue for duplicate submissions" do
    draft = create(:account_activity_import_draft)
    create(:workspace_membership, budget_workspace: draft.budget_workspace, user: draft.user)

    first = described_class.call(draft: draft)
    replay = described_class.call(draft: draft.reload)

    expect(replay).to eq(first)
    expect(enqueued_jobs.count { |job| job[:job] == Accounts::ActivityImports::CommitJob }).to eq(1)
    expect(draft.budget_workspace.operation_runs.count).to eq(1)
  end

  it "recovers a primary operation after the queue is temporarily unavailable" do
    draft = create(:account_activity_import_draft)
    create(:workspace_membership, budget_workspace: draft.budget_workspace, user: draft.user)
    allow(Accounts::ActivityImports::CommitJob).to receive(:perform_later).and_raise(IOError, "queue unavailable")

    operation = described_class.call(draft: draft)

    expect(operation.reload).to have_attributes(state: "pending", enqueued_at: nil)
    expect(operation.last_enqueue_attempt_at).to be_present

    operation.update_column(:last_enqueue_attempt_at, 2.minutes.ago)
    allow(Accounts::ActivityImports::CommitJob).to receive(:perform_later).and_call_original

    expect do
      Platform::Operations::ReconcileDispatchesJob.perform_now
    end.to have_enqueued_job(Accounts::ActivityImports::CommitJob).with(operation.id, draft.id)
    expect(operation.reload.enqueued_at).to be_present
  end
end
