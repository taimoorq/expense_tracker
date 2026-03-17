require "rails_helper"

RSpec.describe EstimateMonthCreditCards do
  it "replaces prior estimates and allocates available cash across the current user's cards" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    create(:expense_entry, budget_month: budget_month, user: user, section: :income, payee: "Salary", planned_amount: 1000, source_file: "manual")
    create(:expense_entry, budget_month: budget_month, user: user, section: :fixed, payee: "Rent", planned_amount: 400, source_file: "manual")
    create(:expense_entry, budget_month: budget_month, user: user, section: :debt, payee: "Old Estimate", planned_amount: 25, source_file: "credit_card_estimate")

    first_card = create(:credit_card, user: user, name: "Visa", minimum_payment: 50, due_day: 10, priority: 1)
    second_card = create(:credit_card, user: user, name: "Mastercard", minimum_payment: 25, due_day: 22, priority: 2)

    created = described_class.new(budget_month: budget_month).call
    estimates = budget_month.expense_entries.where(source_file: "credit_card_estimate").order(:payee)

    expect(created).to eq(2)
    expect(estimates.pluck(:payee)).to contain_exactly(first_card.name, second_card.name)
    expect(estimates.sum(:planned_amount).to_d).to eq(600.to_d)
    expect(estimates.find_by(payee: first_card.name).occurred_on).to eq(Date.new(2026, 3, 10))
    expect(estimates.find_by(payee: second_card.name).occurred_on).to eq(Date.new(2026, 3, 22))
  end

  it "clamps due day to the end of shorter months" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 2, 1), label: "February 2026")
    create(:expense_entry, budget_month: budget_month, user: user, section: :income, payee: "Salary", planned_amount: 500, source_file: "manual")
    create(:credit_card, user: user, name: "Visa", minimum_payment: 50, due_day: 31, priority: 1)

    described_class.new(budget_month: budget_month).call
    estimate = budget_month.expense_entries.find_by(source_file: "credit_card_estimate", payee: "Visa")

    expect(estimate.occurred_on).to eq(Date.new(2026, 2, 28))
  end
end
