require "rails_helper"

RSpec.describe EstimateMonthCreditCards do
  it "replaces prior estimates and allocates available cash across the current user's cards" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    create(:expense_entry, budget_month: budget_month, user: user, section: :income, payee: "Salary", planned_amount: 1000, source_file: "manual")
    create(:expense_entry, budget_month: budget_month, user: user, section: :fixed, payee: "Rent", planned_amount: 400, source_file: "manual")
    create(:expense_entry, budget_month: budget_month, user: user, section: :debt, payee: "Old Estimate", planned_amount: 25, source_file: "credit_card_estimate")

    first_card = create(:credit_card, user: user, name: "Visa", minimum_payment: 50, priority: 1)
    second_card = create(:credit_card, user: user, name: "Mastercard", minimum_payment: 25, priority: 2)

    created = described_class.new(budget_month: budget_month).call
    estimates = budget_month.expense_entries.where(source_file: "credit_card_estimate").order(:payee)

    expect(created).to eq(2)
    expect(estimates.pluck(:payee)).to contain_exactly(first_card.name, second_card.name)
    expect(estimates.sum(:planned_amount).to_d).to eq(600.to_d)
  end
end
