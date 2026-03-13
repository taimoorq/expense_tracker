require "rails_helper"

RSpec.describe "Month generation actions", type: :request do
  let(:user) { create(:user) }
  let(:budget_month) { create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026") }

  before { sign_in user }

  it "generates paychecks from the current user's schedules" do
    create(:pay_schedule, user: user, name: "Acme Payroll", cadence: :monthly, day_of_month_one: 15, first_pay_on: Date.new(2026, 1, 15), amount: 3000)
    other_user = create(:user)
    create(:pay_schedule, user: other_user, name: "Other Payroll", cadence: :monthly, day_of_month_one: 15, first_pay_on: Date.new(2026, 1, 15), amount: 9999)

    expect do
      post generate_paychecks_budget_month_path(budget_month)
    end.to change(budget_month.expense_entries.where(source_file: "pay_schedule"), :count).by(1)

    expect(response).to redirect_to(budget_month_path(budget_month))
    expect(budget_month.expense_entries.last.payee).to eq("Acme Payroll")
  end

  it "generates subscriptions from the current user's templates" do
    create(:subscription, user: user, name: "Netflix", due_day: 8, amount: 21.99)

    expect do
      post generate_subscriptions_budget_month_path(budget_month)
    end.to change(budget_month.expense_entries.where(source_file: "subscription"), :count).by(1)

    expect(response).to redirect_to(budget_month_path(budget_month))
    expect(budget_month.expense_entries.last.payee).to eq("Netflix")
  end

  it "generates monthly bills from the current user's templates" do
    create(:monthly_bill, user: user, name: "Mortgage", due_day: 12, default_amount: 1800)

    expect do
      post generate_monthly_bills_budget_month_path(budget_month)
    end.to change(budget_month.expense_entries.where(source_file: "monthly_bill"), :count).by(1)
  end

  it "generates payment plans from the current user's templates" do
    create(:payment_plan, user: user, name: "IRS Plan", due_day: 20, total_due: 1000, amount_paid: 100, monthly_target: 150)

    expect do
      post generate_payment_plans_budget_month_path(budget_month)
    end.to change(budget_month.expense_entries.where(source_file: "payment_plan"), :count).by(1)
  end

  it "estimates credit cards from the current user's cards" do
    create(:expense_entry, budget_month: budget_month, user: user, section: :income, planned_amount: 1000, payee: "Salary", source_file: "manual")
    create(:credit_card, user: user, name: "Visa", minimum_payment: 50, priority: 1)

    expect do
      post estimate_credit_cards_budget_month_path(budget_month)
    end.to change(budget_month.expense_entries.where(source_file: "credit_card_estimate"), :count).by(1)
  end
end