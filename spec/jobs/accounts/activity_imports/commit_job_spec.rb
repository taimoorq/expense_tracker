require "rails_helper"
require "active_job/continuation/test_helper"

RSpec.describe Accounts::ActivityImports::CommitJob, type: :job do
  include ActiveJob::Continuation::TestHelper

  def dispatched_draft
    draft = create(:account_activity_import_draft)
    create(:workspace_membership, budget_workspace: draft.budget_workspace, user: draft.user)
    operation = Accounts::ActivityImports::Dispatch.call(draft: draft)
    clear_enqueued_jobs
    [ draft.reload, operation ]
  end

  it "commits atomically and replays without duplicate legacy rows" do
    draft, operation = dispatched_draft

    described_class.perform_now(operation.id, draft.id)
    described_class.perform_now(operation.id, draft.id)

    expect(operation.reload).to have_attributes(
      state: "succeeded",
      progress_current: 3,
      progress_total: 3,
      result_counts: include("account_activity_imports" => 1, "account_activities" => 0)
    )
    expect(draft.reload).to be_state_consumed
    expect(draft.preview_payload).to eq({})
    expect(draft.user.account_activity_imports.count).to eq(1)
  end

  it "resumes after a worker stops between validation and commit" do
    draft = create(:account_activity_import_draft)
    create(:workspace_membership, budget_workspace: draft.budget_workspace, user: draft.user)
    operation = Accounts::ActivityImports::Dispatch.call(draft: draft)

    interrupt_job_after_step(described_class, :validate_draft) do
      perform_enqueued_jobs(only: described_class)
    end

    expect(draft.user.account_activity_imports).to be_empty
    expect(operation.reload).to be_state_pending

    perform_enqueued_jobs(only: described_class)

    expect(operation.reload).to be_state_succeeded
    expect(draft.reload).to be_state_consumed
  end

  it "uses the queued operation for target evidence instead of nesting another operation" do
    draft = create(:account_activity_import_draft)
    backfill = Platform::TargetBackfill::Runner.call(user: draft.user)
    backfill.workspace.update!(target_writes_enabled: true)
    operation = Accounts::ActivityImports::Dispatch.call(draft: draft.reload)
    clear_enqueued_jobs

    described_class.perform_now(operation.id, draft.id)

    commit_operations = backfill.workspace.operation_runs.where(
      operation_type: "commit_legacy_account_activity_import"
    )
    expect(commit_operations).to contain_exactly(operation)
    expect(backfill.workspace.import_batches.sole.operation_run).to eq(operation)
  end

  it "marks an invalid queued identity as a terminal retryable failure" do
    draft, operation = dispatched_draft
    operation.update!(job_arguments: [ SecureRandom.uuid ])

    described_class.perform_now(operation.id, draft.id)

    expect(operation.reload).to be_state_failed
    expect(draft.reload).to be_state_failed
  end

  it "uses one shared concurrency group per workspace" do
    first_draft, first_operation = dispatched_draft
    second_draft = create(
      :account_activity_import_draft,
      user: first_draft.user,
      budget_workspace: first_draft.budget_workspace
    )
    second_operation = create(
      :operation_run,
      budget_workspace: first_draft.budget_workspace,
      job_class: described_class.name,
      job_arguments: [ second_draft.id ]
    )
    other_draft, other_operation = dispatched_draft

    first_key = described_class.new(first_operation.id, first_draft.id).concurrency_key
    second_key = described_class.new(second_operation.id, second_draft.id).concurrency_key
    other_key = described_class.new(other_operation.id, other_draft.id).concurrency_key

    expect(first_key).to eq(second_key)
    expect(first_key).to start_with("workspace_mutations/")
    expect(other_key).not_to eq(first_key)
  end
end
