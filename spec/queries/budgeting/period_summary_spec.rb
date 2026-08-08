require "rails_helper"

RSpec.describe Budgeting::PeriodSummary do
  it "calculates plan, actual, remaining, forecast, variance, and unmatched counts from authoritative rows" do
    workspace = create(:budget_workspace)
    period = create(:budget_period, budget_workspace: workspace, starts_on: Date.new(2026, 8, 1))
    income_item = create(:budget_item, budget_workspace: workspace, budget_period: period, flow_kind: "income", planned_amount: 1_000)
    outflow_item = create(:budget_item, budget_workspace: workspace, budget_period: period, flow_kind: "outflow", planned_amount: 600)
    income_transaction = create(:financial_transaction, budget_workspace: workspace, effective_on: Date.new(2026, 8, 5), flow_kind: "income", gross_amount: 900)
    outflow_transaction = create(:financial_transaction, budget_workspace: workspace, effective_on: Date.new(2026, 8, 7), flow_kind: "outflow", gross_amount: 500)
    create(
      :budget_allocation,
      budget_workspace: workspace,
      budget_item: income_item,
      financial_transaction: income_transaction,
      amount: 900
    )
    create(
      :budget_allocation,
      budget_workspace: workspace,
      budget_item: outflow_item,
      financial_transaction: outflow_transaction,
      amount: 500
    )
    create(:financial_transaction, budget_workspace: workspace, effective_on: Date.new(2026, 8, 9), gross_amount: 25)

    summary = described_class.call(period: period)

    expect(summary).to have_attributes(
      planned_income: 1_000,
      planned_outflow: 600,
      planned_net: 400,
      actual_income: 900,
      actual_outflow: 500,
      actual_net: 400,
      remaining_income: 100,
      remaining_outflow: 100,
      forecast_income: 1_000,
      forecast_outflow: 600,
      forecast_net: 400,
      income_variance: -100,
      outflow_variance: -100,
      unmatched_count: 1
    )
  end
end
