require "rails_helper"

RSpec.describe Platform::TargetSync::ExpenseEntryWriter do
  def prepare_target(user)
    result = Platform::TargetBackfill::Runner.call(user: user)
    expect(result).to be_success
    result.workspace.update!(target_writes_enabled: true)
    result.workspace
  end

  def create_entry(user:, month:, attributes: {})
    ExpenseEntries::Creator.call(
      user: user,
      budget_month: month,
      expense_entry_params: {
        occurred_on: month.month_on + 4.days,
        section: "variable",
        category: "Groceries",
        payee: "Market",
        planned_amount: "75.00",
        status: "planned",
        source_file: "manual"
      }.merge(attributes),
      planning_template_params: {},
      recurring_link_token: nil
    )
  end

  it "atomically maps a newly created legacy entry into its target period and plan item" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    workspace = prepare_target(user)

    result = create_entry(user: user, month: month)

    expect(result).to be_success
    mapping = workspace.legacy_record_mappings.find_by!(
      legacy_record_type: "ExpenseEntry",
      legacy_record_id: result.expense_entry.id,
      target_record_type: "BudgetItem"
    )
    item = BudgetItem.find(mapping.target_record_id)
    expect(item).to have_attributes(
      budget_period: workspace.budget_periods.find_by!(starts_on: month.month_on),
      planned_amount: 75.to_d,
      flow_kind: "outflow",
      budget_group: "variable",
      origin_kind: "manual",
      category_snapshot: "Groceries"
    )
    expect(workspace.operation_runs.where(operation_type: "sync_legacy_expense_entry").count).to eq(1)
  end

  it "keeps paid transfer postings in parity and reverses the actual when the entry becomes planned" do
    user = create(:user)
    source = create(:account, user: user, kind: :checking, name: "Checking")
    destination = create(:account, user: user, kind: :savings, name: "Savings")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    workspace = prepare_target(user)

    result = create_entry(
      user: user,
      month: month,
      attributes: {
        section: "manual",
        category: "Savings transfer",
        source_account_id: source.id,
        destination_account_id: destination.id,
        actual_amount: "80.00",
        status: "paid"
      }
    )
    transaction = workspace.financial_transactions.find_by!(idempotency_key: "legacy:expense-entry:#{result.expense_entry.id}")

    expect(transaction).to be_flow_kind_transfer
    expect(transaction.account_postings.order(:sequence_number).pluck(:account_id, :amount, :role)).to eq(
      [ [ source.id, -80.to_d, "source" ], [ destination.id, 80.to_d, "destination" ] ]
    )
    expect(transaction.budget_allocations.sole.amount).to eq(80.to_d)

    updated = ExpenseEntries::Updater.call(
      expense_entry: result.expense_entry,
      params: { status: "planned", actual_amount: nil },
      mark_as_paid: false
    )

    expect(updated).to be(true)
    expect(transaction.reload).to be_state_reversed
    expect(Budgeting::PeriodSummary.call(period: workspace.budget_periods.sole).actual_outflow).to eq(0)
  end

  it "rolls back the legacy write when a paid entry cannot produce valid account evidence" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    workspace = prepare_target(user)

    expect do
      @result = create_entry(
        user: user,
        month: month,
        attributes: { actual_amount: "75.00", status: "paid" }
      )
    end.not_to change(ExpenseEntry, :count)

    expect(@result).not_to be_success
    expect(@result.expense_entry.errors.full_messages).to include(
      "A paid entry must identify every affected account"
    )
    expect(workspace.financial_transactions).to be_empty
  end

  it "leaves the target untouched while target writes are disabled" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace

    result = create_entry(user: user, month: month)

    expect(result).to be_success
    expect(
      workspace.legacy_record_mappings.where(
        legacy_record_type: "ExpenseEntry",
        legacy_record_id: result.expense_entry.id
      )
    ).to be_empty
  end

  it "synchronizes an entry-wizard template in the same transaction as its first item" do
    user = create(:user)
    account = create(:account, user: user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    workspace = prepare_target(user)

    result = ExpenseEntries::Creator.call(
      user: user,
      budget_month: month,
      expense_entry_params: {
        occurred_on: Date.new(2026, 8, 8),
        section: "fixed",
        category: "Streaming",
        payee: "Video",
        planned_amount: "19.99",
        source_account_id: account.id,
        status: "planned",
        source_file: "manual"
      },
      planning_template_params: { enabled: "1", template_type: "subscription", due_day: "8" },
      recurring_link_token: nil
    )

    expect(result).to be_success
    expect(workspace.planning_templates.sole.name).to eq("Video")
    expect(workspace.budget_items.sole.name_snapshot).to eq("Video")
  end
end
