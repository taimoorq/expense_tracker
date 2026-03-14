require "rails_helper"

RSpec.describe "imported template matching" do
  it "prevents duplicate generation when imported rows already match templates" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

    create(:pay_schedule,
           user: user,
           name: "Employer",
           cadence: :semimonthly,
           amount: 4200,
           first_pay_on: Date.new(2026, 3, 7),
           day_of_month_one: 7,
           day_of_month_two: 22,
           weekend_adjustment: :no_adjustment)
    create(:subscription, user: user, name: "Netflix", amount: 21.19, due_day: 19, account: "Card")
    create(:monthly_bill, user: user, name: "Mortgage", kind: :fixed_payment, due_day: 31, account: "Checking")
    create(:payment_plan, user: user, name: "Apple Financing", total_due: 1200, amount_paid: 300, monthly_target: 107.41, due_day: 15, account: "Card")

    create(:expense_entry,
           budget_month: budget_month,
           user: user,
           source_file: "March 2026 Transactions.csv",
           occurred_on: Date.new(2026, 3, 7),
           section: :income,
           category: "Paycheck",
           payee: "Employer",
           planned_amount: 4200,
           actual_amount: 4200,
           account: "Checking",
           status: :paid)
    create(:expense_entry,
           budget_month: budget_month,
           user: user,
           source_file: "March 2026 Transactions.csv",
           occurred_on: Date.new(2026, 3, 22),
           section: :income,
           category: "Paycheck",
           payee: "Employer",
           planned_amount: 4200,
           actual_amount: 4200,
           account: "Checking",
           status: :paid)
    create(:expense_entry,
           budget_month: budget_month,
           user: user,
           source_file: "March 2026 Transactions.csv",
           occurred_on: Date.new(2026, 3, 19),
           section: :fixed,
           category: "Subscription",
           payee: "Netflix",
           planned_amount: 21.19,
           account: "Card",
           status: :planned)
    create(:expense_entry,
           budget_month: budget_month,
           user: user,
           source_file: "March 2026 Transactions.csv",
           occurred_on: Date.new(2026, 3, 31),
           section: :manual,
           category: "Housing",
           payee: "Mortgage",
           planned_amount: 3394.65,
           actual_amount: 3394.65,
           account: "Checking",
           status: :paid)
    create(:expense_entry,
           budget_month: budget_month,
           user: user,
           source_file: "March 2026 Transactions.csv",
           occurred_on: Date.new(2026, 3, 15),
           section: :debt,
           category: "Installment",
           payee: "Apple Financing",
           planned_amount: 107.41,
           actual_amount: 107.41,
           account: "Card",
           status: :paid)

    expect(GenerateMonthPaychecks.new(budget_month: budget_month).call).to eq(0)
    expect(GenerateMonthSubscriptions.new(budget_month: budget_month).call).to eq(0)
    expect(GenerateMonthMonthlyBills.new(budget_month: budget_month).call).to eq(0)
    expect(GenerateMonthPaymentPlans.new(budget_month: budget_month).call).to eq(0)

    expect(budget_month.expense_entries.where(source_file: "pay_schedule")).to be_empty
    expect(budget_month.expense_entries.where(source_file: "subscription")).to be_empty
    expect(budget_month.expense_entries.where(source_file: "monthly_bill")).to be_empty
    expect(budget_month.expense_entries.where(source_file: "payment_plan")).to be_empty
  end
end