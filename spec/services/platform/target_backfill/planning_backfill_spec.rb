require "rails_helper"

RSpec.describe Platform::TargetBackfill::PlanningBackfill do
  it "backfills periods, plans, templates, recurrence, and durable occurrences" do
    user = create(:user)
    account = create(:account, user: user, name: "Checking")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    schedule = create(
      :pay_schedule,
      user: user,
      name: "Payroll",
      first_pay_on: Date.new(2026, 3, 15),
      day_of_month_one: 15,
      linked_account: account
    )
    Recurring::GenerateMonthRecurringEntries.new(budget_month: month, templates: [ schedule ]).call
    generated_entry = month.expense_entries.find_by!(source_template: schedule)
    manual_entry = create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      category: "Groceries",
      planned_amount: 200
    )

    result = described_class.call(user: user)

    workspace = result.workspace
    expect(workspace.budget_periods.sole.starts_on).to eq(month.month_on)
    expect(workspace.budget_items.count).to eq(2)
    expect(workspace.categories.pluck(:name)).to include("Groceries", "Paycheck")
    target_template = workspace.planning_templates.find_by!(name: "Payroll")
    expect(target_template.id).to eq(schedule.id)
    expect(target_template.recurrence_rule).to have_attributes(cadence: "monthly", day_one: 15)
    occurrence = workspace.recurring_occurrences.sole
    expect(occurrence).to be_state_materialized
    expect(occurrence.budget_item.recurring_occurrence).to eq(occurrence)
    expect(
      LegacyRecordMapping.where(
        legacy_record_type: "ExpenseEntry",
        legacy_record_id: generated_entry.id,
        target_record_type: %w[BudgetItem RecurringOccurrence]
      ).distinct.count(:target_record_type)
    ).to eq(2)
    expect(manual_entry.reload.budget_workspace).to eq(workspace)
  end

  it "is idempotent and retains separate detail semantics for similarly named templates" do
    user = create(:user)
    create(:subscription, user: user, name: "Shared name")
    payment_plan = create(:payment_plan, user: user, name: "Shared name", total_due: 500, amount_paid: 125, monthly_target: 50)

    first = described_class.call(user: user)
    first_counts = {
      templates: first.workspace.planning_templates.count,
      rules: RecurrenceRule.count,
      terms: PaymentPlanTerm.count,
      mappings: LegacyRecordMapping.count
    }
    described_class.call(user: user)

    expect(first.workspace.reload.planning_templates.where(name: "Shared name").count).to eq(2)
    expect(first.workspace.planning_templates.count).to eq(first_counts[:templates])
    expect(RecurrenceRule.count).to eq(first_counts[:rules])
    expect(PaymentPlanTerm.count).to eq(first_counts[:terms])
    expect(LegacyRecordMapping.count).to eq(first_counts[:mappings])
    term = Platform::TargetBackfill::MappingStore
      .new(workspace: first.workspace, operation_run: first.operation_run)
      .target_for(source: payment_plan, target_class: PlanningTemplate)
      .payment_plan_term
    expect(term).to have_attributes(total_due: 500, opening_paid_adjustment: 125, monthly_target: 50)
  end
end
