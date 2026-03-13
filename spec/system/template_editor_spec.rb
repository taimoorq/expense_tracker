require "rails_helper"

RSpec.describe "Template editor", type: :system do
  it "renders the template editor modal and updates the source template" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    schedule = create(:pay_schedule,
      user: user,
      name: "Acme Payroll",
      amount: 2500,
      cadence: :monthly,
      first_pay_on: Date.new(2026, 1, 15),
      day_of_month_one: 15)
    create(:expense_entry,
      budget_month: budget_month,
      user: user,
      occurred_on: Date.new(2026, 3, 15),
      section: :income,
      category: "Paycheck",
      payee: schedule.name,
      planned_amount: 2500,
      status: :planned,
      source_file: "pay_schedule")

    sign_in_as(user)

    visit edit_template_budget_month_expense_entry_path(budget_month, budget_month.expense_entries.last)

    expect(page).to have_content("Edit Template: Pay schedule")
    fill_in "pay_schedule_amount", with: "3200"
    click_button "Save"

    expect(page).to have_content("Template updated.")
    expect(schedule.reload.amount.to_d).to eq(3200.to_d)
  end
end