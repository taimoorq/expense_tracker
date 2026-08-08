require "rails_helper"

RSpec.describe Accounts::ReverseImport do
  it "reverses only the selected batch and replays without a second mutation" do
    workspace = create(:budget_workspace)
    membership = create(:workspace_membership, budget_workspace: workspace)
    account = create(:workspace_account, budget_workspace: workspace, user: membership.user)
    operation = create(:operation_run, budget_workspace: workspace, state: "succeeded", completed_at: Time.current)
    batch = ImportBatch.create!(
      budget_workspace: workspace,
      account: account,
      operation_run: operation,
      actor_membership: membership,
      import_kind: "account_activity",
      original_filename: "activity.csv",
      file_digest: Digest::SHA256.hexdigest("activity.csv"),
      idempotency_key: "import-1",
      parser_version: "v1",
      mapping_version: "v1",
      fingerprint_version: "v1",
      status: "committed",
      row_count: 1,
      imported_count: 1,
      duplicate_count: 0,
      error_count: 0,
      committed_at: Time.current
    )
    row = ImportRow.create!(
      budget_workspace: workspace,
      import_batch: batch,
      row_number: 1,
      fingerprint: Digest::SHA256.hexdigest("row"),
      fingerprint_version: "v1",
      normalization_result: "normalized",
      status: "accepted"
    )
    transaction = create(:financial_transaction, budget_workspace: workspace, import_row: row)
    row.update!(financial_transaction: transaction)
    create(:account_posting, budget_workspace: workspace, financial_transaction: transaction, account: account)
    observation = create(
      :balance_observation,
      budget_workspace: workspace,
      account: account,
      source_import_batch: batch
    )

    first = described_class.call(
      workspace: workspace,
      actor_membership: membership,
      import_batch: batch,
      idempotency_key: "reverse-import-1"
    )
    replay = described_class.call(
      workspace: workspace,
      actor_membership: membership,
      import_batch: batch,
      idempotency_key: "reverse-import-1"
    )

    expect(first.value).to be_status_reverted
    expect(replay).to be_replayed
    expect(row.reload).to be_status_reversed
    expect(transaction.reload).to be_state_reversed
    expect(observation.reload).to be_status_superseded
    expect(first.operation_run.audit_events.sole.action).to eq("import_reversal")
  end
end
