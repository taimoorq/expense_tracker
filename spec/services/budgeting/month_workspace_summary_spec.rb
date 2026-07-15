require "rails_helper"

RSpec.describe Budgeting::MonthWorkspaceSummary do
  it "separates planned and actual outflow and reuses the month review query" do
    month = create(:budget_month)
    create(:expense_entry, budget_month: month, user: month.user, section: :income, planned_amount: 2_000, actual_amount: 2_100, status: :paid)
    create(:expense_entry, budget_month: month, user: month.user, section: :fixed, planned_amount: 500, actual_amount: 475, status: :paid)
    create(:expense_entry, budget_month: month, user: month.user, section: :variable, planned_amount: 200, actual_amount: nil, status: :planned, occurred_on: Date.current)

    result = described_class.call(budget_month: month, expense_entries: month.expense_entries.to_a)

    expect(result.income).to eq(2_100)
    expect(result.planned_outflow).to eq(700)
    expect(result.actual_outflow).to eq(475)
    expect(result.leftover).to eq(1_425)
    expect(result.review_count).to be_positive
    expect(result.actual_coverage_count).to eq(1)
    expect(result.outflow_count).to eq(2)
  end
end
