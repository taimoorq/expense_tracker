require "rails_helper"

RSpec.describe BudgetMonth, type: :model do
  describe "#income_total" do
    it "uses the month-level planned income when there are no income entries" do
      budget_month = create(:budget_month, planned_income: 4200)

      expect(budget_month.income_total.to_d).to eq(4200.to_d)
    end

    it "prefers income entries over the month-level planned income" do
      budget_month = create(:budget_month, planned_income: 8400)
      create(:expense_entry,
        budget_month: budget_month,
        user: budget_month.user,
        section: :income,
        payee: "West Monroe",
        planned_amount: 4200,
        occurred_on: Date.new(2026, 3, 6))
      create(:expense_entry,
        budget_month: budget_month,
        user: budget_month.user,
        section: :income,
        payee: "West Monroe",
        planned_amount: 1000,
        occurred_on: Date.new(2026, 3, 13))
      create(:expense_entry,
        budget_month: budget_month,
        user: budget_month.user,
        section: :income,
        payee: "West Monroe",
        planned_amount: 4200,
        occurred_on: Date.new(2026, 3, 20))

      expect(budget_month.income_total.to_d).to eq(9400.to_d)
    end

    it "prefers itemized actual amounts when income entries are paid" do
      budget_month = create(:budget_month, actual_income: 5000)
      create(:expense_entry,
        budget_month: budget_month,
        user: budget_month.user,
        section: :income,
        payee: "Bonus",
        planned_amount: 1000,
        actual_amount: 1200,
        status: :paid,
        occurred_on: Date.new(2026, 3, 13))

      expect(budget_month.income_total.to_d).to eq(1200.to_d)
    end
  end
end
