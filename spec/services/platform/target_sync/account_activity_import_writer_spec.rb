require "rails_helper"

RSpec.describe Platform::TargetSync::AccountActivityImportWriter do
  def preview(account_delta: -25)
    {
      ok: true,
      original_filename: "activity.csv",
      file_digest: Digest::SHA256.hexdigest("activity.csv"),
      commit_idempotency_key: Digest::SHA256.hexdigest("activity.csv:commit"),
      header_row_number: 1,
      headers: [ "Date", "Description", "Amount" ],
      column_mapping: { transaction_on: "Date", description: "Description", raw_amount: "Amount" },
      amount_strategy: "charges_are_negative",
      started_on: "2026-08-04",
      ended_on: "2026-08-04",
      institution_balance: "975.00",
      institution_balance_as_of: "2026-08-04",
      rows: [
        {
          transaction_on: "2026-08-04",
          posted_on: "2026-08-04",
          description: "Market",
          category: "Groceries",
          activity_type: "purchase",
          raw_amount: account_delta.to_s,
          amount: account_delta.abs.to_s,
          account_delta: account_delta.to_s,
          row_number: 2,
          fingerprint: Digest::SHA256.hexdigest("activity.csv:row:2:#{account_delta}"),
          raw_payload: { "Date" => "2026-08-04", "Description" => "Market" }
        }
      ],
      warnings: []
    }
  end

  it "commits legacy evidence and one canonical transaction/posting atomically and replayably" do
    user = create(:user)
    account = create(:account, user: user)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.update!(target_writes_enabled: true)
    account.reload

    first = Accounts::ActivityImports::Importer.new(user: user, account: account, preview: preview).call
    replay = Accounts::ActivityImports::Importer.new(user: user, account: account, preview: preview).call

    expect(first).to include(ok: true, imported_count: 1, duplicate_count: 0, replayed: false)
    expect(replay).to include(ok: true, imported_count: 1, duplicate_count: 0, replayed: true)
    expect(workspace.import_batches.sole).to have_attributes(status: "committed", imported_count: 1)
    expect(workspace.import_rows.sole.financial_transaction).to eq(workspace.financial_transactions.sole)
    expect(workspace.account_postings.sole).to have_attributes(account: account, amount: -25.to_d)
    expect(workspace.balance_observations.status_trusted.sole).to have_attributes(
      account: account,
      balance: 975.to_d,
      source_kind: "institution_file"
    )
    expect(workspace.operation_runs.where(operation_type: "commit_legacy_account_activity_import").count).to eq(1)
  end

  it "rolls back the legacy import when a row cannot produce a valid posting" do
    user = create(:user)
    account = create(:account, user: user)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.update!(target_writes_enabled: true)
    account.reload

    result = Accounts::ActivityImports::Importer.new(
      user: user,
      account: account,
      preview: preview(account_delta: 0)
    ).call

    expect(result.fetch(:ok)).to be(false)
    expect(AccountActivityImport.where(user: user)).to be_empty
    expect(AccountActivity.where(account: account)).to be_empty
    expect(workspace.import_batches).to be_empty
    expect(workspace.financial_transactions).to be_empty
  end
end
