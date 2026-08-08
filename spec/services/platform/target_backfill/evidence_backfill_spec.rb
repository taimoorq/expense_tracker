require "rails_helper"

RSpec.describe Platform::TargetBackfill::EvidenceBackfill do
  it "normalizes snapshots, imports, postings, and paid-plan allocations without double counting" do
    user = create(:user)
    account = create(:account, user: user, kind: :checking)
    create(:account_snapshot, account: account, recorded_on: Date.new(2026, 2, 28), balance: 1_000)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1))
    imported_entry = create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      occurred_on: Date.new(2026, 3, 5),
      planned_amount: 40,
      actual_amount: 42.50,
      status: :paid
    )
    manual_entry = create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      occurred_on: Date.new(2026, 3, 8),
      planned_amount: 75,
      actual_amount: 70,
      status: :paid
    )
    legacy_import = create(
      :account_activity_import,
      user: user,
      account: account,
      metadata: {
        "institution_balance" => "957.50",
        "institution_balance_as_of" => "2026-03-05"
      }
    )
    activity = create(
      :account_activity,
      user: user,
      account: account,
      account_activity_import: legacy_import,
      expense_entry: imported_entry,
      amount: 42.50,
      account_delta: -42.50,
      transaction_on: Date.new(2026, 3, 5)
    )

    result = described_class.call(user: user)

    workspace = result.workspace
    expect(workspace.balance_observations.count).to eq(2)
    expect(workspace.import_batches.sole.status).to eq("committed")
    expect(workspace.import_rows.sole.financial_transaction.origin_kind).to eq("institution_import")
    expect(workspace.financial_transactions.count).to eq(2)
    expect(workspace.account_postings.pluck(:amount)).to contain_exactly(-42.50, -70)
    expect(workspace.budget_allocations.count).to eq(2)
    imported_transaction = Platform::TargetBackfill::MappingStore
      .new(workspace: workspace, operation_run: result.operation_run)
      .target_for(source: activity, target_class: FinancialTransaction)
    expect(imported_transaction.budget_allocations.sole.budget_item).to eq(
      Platform::TargetBackfill::MappingStore
        .new(workspace: workspace, operation_run: result.operation_run)
        .target_for(source: imported_entry, target_class: BudgetItem)
    )
    expect(
      Platform::TargetBackfill::MappingStore
        .new(workspace: workspace, operation_run: result.operation_run)
        .target_for(source: manual_entry, target_class: FinancialTransaction)
        .gross_amount
    ).to eq(70)
  end

  it "is idempotent and creates equal-and-opposite transfer postings" do
    user = create(:user)
    checking = create(:account, user: user, kind: :checking)
    savings = create(:account, user: user, kind: :savings)
    month = create(:budget_month, user: user)
    create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: checking,
      destination_account: savings,
      planned_amount: 100,
      actual_amount: 100,
      status: :paid
    )

    first = described_class.call(user: user)
    first_counts = [ FinancialTransaction.count, AccountPosting.count, BudgetAllocation.count, LegacyRecordMapping.count ]
    described_class.call(user: user)

    expect([ FinancialTransaction.count, AccountPosting.count, BudgetAllocation.count, LegacyRecordMapping.count ]).to eq(first_counts)
    expect(first.workspace.account_postings.order(:sequence_number).pluck(:amount)).to eq([ -100, 100 ])
  end
end
