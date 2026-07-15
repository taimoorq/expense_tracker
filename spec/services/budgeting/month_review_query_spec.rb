require "rails_helper"

RSpec.describe Budgeting::MonthReviewQuery do
  it "returns server-defined counts and the entries for a selected review reason" do
    user = create(:user)
    month = create(:budget_month, user: user)
    due_and_incomplete = create(
      :expense_entry,
      budget_month: month,
      user: user,
      occurred_on: Date.current,
      category: nil,
      payee: nil,
      status: :planned
    )
    missing_actual = create(
      :expense_entry,
      budget_month: month,
      user: user,
      occurred_on: Date.current,
      category: "Utilities",
      payee: "Power Company",
      status: :paid,
      actual_amount: nil
    )

    result = described_class.call(entries: month.expense_entries.to_a, reason: "due", today: Date.current)

    expect(result).to be_active
    expect(result.selected_reason).to eq("due")
    expect(result.entries).to eq([ due_and_incomplete ])
    expect(result.counts).to include(due: 1, missing_details: 1, missing_actual: 1, auto_completed: 0, all: 3)
    expect(result.entries).not_to include(missing_actual)
  end

  it "deduplicates entries in all mode while preserving the total number of issues" do
    user = create(:user)
    month = create(:budget_month, user: user)
    entry = create(
      :expense_entry,
      budget_month: month,
      user: user,
      occurred_on: Date.current,
      category: nil,
      payee: nil,
      status: :planned
    )

    result = described_class.call(entries: [ entry ], reason: "all", today: Date.current)

    expect(result.issue_count).to eq(2)
    expect(result.entries).to eq([ entry ])
  end

  it "ignores unknown reasons instead of letting them change the query" do
    result = described_class.call(entries: [], reason: "unknown")

    expect(result).not_to be_active
    expect(result.selected_reason).to be_nil
    expect(result.entries).to be_empty
  end
end
