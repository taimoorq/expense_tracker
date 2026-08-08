require "rails_helper"

RSpec.describe ExpenseEntries::Destroyer do
  def prepare_target(user)
    result = Platform::TargetBackfill::Runner.call(user: user)
    expect(result).to be_success
    result.workspace.update!(target_writes_enabled: true)
    result.workspace
  end

  it "voids mapped planning and ledger records before deleting the legacy entry" do
    user = create(:user)
    account = create(:account, user: user, kind: :checking)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    entry = create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      status: :paid,
      actual_amount: 125,
      occurred_on: Date.new(2026, 8, 8)
    )
    workspace = prepare_target(user)
    item = mapped_record(workspace, entry, BudgetItem)
    transaction = mapped_record(workspace, entry, FinancialTransaction)

    expect(described_class.call(expense_entry: entry)).to be(true)

    expect(ExpenseEntry.exists?(entry.id)).to be(false)
    expect(item.reload).to have_attributes(state: "voided", void_reason: "Deleted from legacy plan")
    expect(transaction.reload).to be_state_reversed
    expect(
      workspace.legacy_record_mappings.where(legacy_record_type: "ExpenseEntry", legacy_record_id: entry.id).distinct.pluck(:status)
    ).to eq([ "omitted" ])
    expect(workspace.audit_events.where(entity_type: "BudgetItem", entity_id: item.id, action: "void")).to exist
  end

  it "keeps both models unchanged when the target period is closed" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    entry = create(:expense_entry, user: user, budget_month: month)
    workspace = prepare_target(user)
    mapped_record(workspace, month, BudgetPeriod).update!(state: "closed")

    expect(described_class.call(expense_entry: entry)).to be(false)

    expect(ExpenseEntry.exists?(entry.id)).to be(true)
    expect(mapped_record(workspace, entry, BudgetItem).reload).to be_state_open
    expect(entry.errors.full_messages).to include("Reopen #{month.label} before deleting its plan")
  end

  it "preserves legacy behavior while target writes are disabled" do
    user = create(:user)
    month = create(:budget_month, user: user)
    entry = create(:expense_entry, user: user, budget_month: month)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace

    expect(described_class.call(expense_entry: entry)).to be(true)

    expect(ExpenseEntry.exists?(entry.id)).to be(false)
    expect(workspace.operation_runs.where(operation_type: "void_legacy_expense_entry")).to be_empty
  end

  def mapped_record(workspace, source, target_class)
    mapping = workspace.legacy_record_mappings.find_by!(
      legacy_record_type: source.class.name,
      legacy_record_id: source.id,
      target_record_type: target_class.name
    )
    target_class.find(mapping.target_record_id)
  end
end
