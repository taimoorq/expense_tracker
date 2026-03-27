require "rails_helper"

RSpec.describe MonthCashflowSankey do
  it "builds a month-level sankey payload from income, outflow, and leftover" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 4, 1), label: "April 2026")
    create(:expense_entry, budget_month: budget_month, user: user, section: :income, payee: "Main Paycheck", planned_amount: 4000)
    create(:expense_entry, budget_month: budget_month, user: user, section: :fixed, category: "Housing", payee: "Rent", planned_amount: 1500)
    create(:expense_entry, budget_month: budget_month, user: user, section: :variable, category: "Groceries", payee: "Trader Joe's", planned_amount: 400)

    payload = described_class.new(budget_month: budget_month).payload

    expect(payload[:nodes]).to include({ name: "Main Paycheck" }, { name: "Income" }, { name: "Housing" }, { name: "Groceries" }, { name: "Leftover" })
    expect(payload[:links]).to include(
      { source: "Main Paycheck", target: "Income", value: 4000.0 },
      { source: "Income", target: "Housing", value: 1500.0 },
      { source: "Income", target: "Groceries", value: 400.0 }
    )
    expect(payload[:income_total]).to eq(4000.0)
    expect(payload[:outflow_total]).to eq(1900.0)
    expect(payload[:leftover_total]).to eq(2100.0)
  end

  it "folds lower-ranked outflow buckets into Other Outflow when there are many categories" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 4, 1), label: "April 2026")
    create(:expense_entry, budget_month: budget_month, user: user, section: :income, payee: "Main Paycheck", planned_amount: 5000)

    10.times do |index|
      create(:expense_entry,
        budget_month: budget_month,
        user: user,
        section: :variable,
        category: "Category #{index}",
        payee: "Expense #{index}",
        planned_amount: 100 + index)
    end

    payload = described_class.new(budget_month: budget_month, category_limit: 3).payload

    expect(payload[:nodes]).to include({ name: "Other Outflow" })
    other_link = payload[:links].find { |link| link[:target] == "Other Outflow" }
    expect(other_link).to be_present
    expect(other_link[:value]).to be > 0
  end
end
