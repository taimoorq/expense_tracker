require "rails_helper"

RSpec.describe BudgetMonth, type: :model do
  describe "#income_total" do
    it "returns 0 when there are no income entries" do
      budget_month = create(:budget_month)
      expect(budget_month.income_total.to_d).to eq(0.to_d)
    end
    it "sums planned_amount for income entries" do
      budget_month = create(:budget_month)
      create(:expense_entry,
        budget_month: budget_month,
        user: budget_month.user,
        section: :income,
        planned_amount: 1000,
        occurred_on: Date.new(2026, 3, 13))
      create(:expense_entry,
        budget_month: budget_month,
        user: budget_month.user,
        section: :income,
        planned_amount: 1200,
        occurred_on: Date.new(2026, 3, 20))
      expect(budget_month.income_total.to_d).to eq(2200.to_d)
    end
  end
end
