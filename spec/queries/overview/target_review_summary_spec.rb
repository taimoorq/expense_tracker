require "rails_helper"

RSpec.describe Overview::TargetReviewSummary do
  it "derives bounded attention and linkage counts from target plan and allocation facts" do
    workspace = create(:budget_workspace)
    account = create(:workspace_account, budget_workspace: workspace)
    period = create(:budget_period, budget_workspace: workspace, starts_on: Date.new(2026, 8, 1))
    due = create(
      :budget_item,
      budget_workspace: workspace,
      budget_period: period,
      scheduled_on: Date.new(2026, 8, 5),
      category_snapshot: "Utilities",
      payee_snapshot: "Power",
      planned_amount: 100
    )
    create(
      :budget_item,
      budget_workspace: workspace,
      budget_period: period,
      scheduled_on: Date.new(2026, 8, 12),
      category_snapshot: "Food",
      payee_snapshot: "Market",
      planned_amount: 50
    )
    create(
      :budget_item,
      budget_workspace: workspace,
      budget_period: period,
      scheduled_on: Date.new(2026, 8, 25),
      category_snapshot: nil,
      payee_snapshot: nil,
      planned_amount: 25
    )
    paid = create(
      :budget_item,
      budget_workspace: workspace,
      budget_period: period,
      intended_source_account: account,
      scheduled_on: Date.new(2026, 8, 3),
      category_snapshot: "Housing",
      payee_snapshot: "Rent",
      planned_amount: 500
    )
    transaction = create(:financial_transaction, budget_workspace: workspace, effective_on: Date.new(2026, 8, 3), gross_amount: 500)
    create(
      :budget_allocation,
      budget_workspace: workspace,
      budget_item: paid,
      financial_transaction: transaction,
      amount: 500
    )

    payload = nil
    queries = count_select_queries do
      payload = described_class.call(period: period, today: Date.new(2026, 8, 7))
    end

    expect(queries).to be <= 3
    expect(payload).to include(
      due_planned_count: 1,
      due_soon_count: 1,
      missing_details_count: 1,
      paid_missing_actual_count: 0,
      auto_completed_count: 0,
      review_attention_count: 2,
      manual_entries_count: 4,
      linked_entries_count: 1,
      linked_paid_entries_count: 1,
      calculation_version: "target-v1"
    )
    expect(due).to be_persisted
  end
end
