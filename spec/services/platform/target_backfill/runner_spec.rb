require "rails_helper"

RSpec.describe Platform::TargetBackfill::Runner do
  it "completes a clean, idempotent backfill without enabling target reads" do
    user = create(:user)
    account = create(:account, user: user)
    create(:account_snapshot, account: account)
    month = create(:budget_month, user: user)
    create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      planned_amount: 50,
      actual_amount: 45,
      status: :paid
    )

    result = described_class.call(user: user)
    target_counts = [ BudgetWorkspace.count, BudgetItem.count, FinancialTransaction.count, AccountPosting.count, BudgetAllocation.count ]
    replay = described_class.call(user: user)

    expect(result).to be_success
    expect(result.verification).to be_clean
    expect(result.operation_run.reload).to be_state_succeeded
    expect(result.workspace).to have_attributes(
      target_backfill_version: Platform::TargetBackfill::WorkspaceBootstrap::VERSION,
      target_reads_enabled: false,
      target_writes_enabled: false
    )
    expect(result.workspace.target_backfilled_at).to be_present
    expect(replay).to be_success
    expect([ BudgetWorkspace.count, BudgetItem.count, FinancialTransaction.count, AccountPosting.count, BudgetAllocation.count ]).to eq(target_counts)
  end

  it "fails parity and preserves an unmatched paid entry inside import coverage for review" do
    user = create(:user)
    account = create(:account, user: user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1))
    entry = create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      occurred_on: Date.new(2026, 3, 8),
      actual_amount: 25,
      status: :paid
    )
    create(
      :account_activity_import,
      user: user,
      account: account,
      rows_count: 0,
      imported_count: 0,
      started_on: Date.new(2026, 3, 1),
      ended_on: Date.new(2026, 3, 31)
    )

    result = described_class.call(user: user)

    expect(result).not_to be_success
    expect(result.operation_run.reload).to be_state_failed
    expect(result.workspace.target_backfilled_at).to be_nil
    expect(
      result.workspace.migration_discrepancies.status_open.find_by(
        legacy_record_type: "ExpenseEntry",
        legacy_record_id: entry.id,
        code: "paid_entry_unmatched_in_import_coverage"
      )
    ).to be_present
    expect(
      result.workspace.legacy_record_mappings.where(
        legacy_record_type: "ExpenseEntry",
        legacy_record_id: entry.id,
        target_record_type: "FinancialTransaction"
      )
    ).to be_empty
  end
end
