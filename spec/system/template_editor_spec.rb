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

    expect(page).to have_content("Edit Recurring: Pay schedule")
    fill_in "pay_schedule_amount", with: "3200"
    click_button "Save"

    expect(page).to have_content("Recurring item updated.")
    expect(schedule.reload.amount.to_d).to eq(3200.to_d)
  end

  it "updates a planning template inline from the planning templates page" do
    user = create(:user)
    schedule = create(:pay_schedule,
      user: user,
      name: "Acme Payroll",
      amount: 2500,
      cadence: :monthly,
      first_pay_on: Date.new(2026, 1, 15),
      day_of_month_one: 15)

    sign_in_as(user)
    visit planning_templates_path

    find("a[aria-label='Edit schedule']").click

    expect(page).to have_current_path(
      edit_pay_schedule_planning_templates_path(schedule),
      ignore_query: false
    )
    expect(page).to have_content("Editing Acme Payroll")
    expect(page).to have_button("Update Schedule")

    fill_in "Employer / Source", with: "Updated Payroll"
    fill_in "pay_schedule_amount", with: "3200"
    click_button "Update Schedule"

    expect(page).to have_current_path(planning_templates_path, ignore_query: false)
    expect(page).to have_content("Pay schedule updated.")
    expect(page).to have_content("Updated Payroll")
    expect(schedule.reload.name).to eq("Updated Payroll")
    expect(schedule.amount.to_d).to eq(3200.to_d)
  end

  it "shows a newly created planning template in the list immediately" do
    user = create(:user)

    sign_in_as(user)
    visit planning_templates_path

    expect(page).to have_no_field("Employer / Source")
    find("summary", text: "Add Schedule").click

    fill_in "Employer / Source", with: "Acme Payroll"
    fill_in "pay_schedule_amount", with: "2500"
    fill_in "First Pay On", with: "2026-01-15"
    fill_in "Day #1", with: "15"

    expect do
      click_button "Save Schedule"
      expect(page).to have_content("Pay schedule saved.")
    end.to change { user.pay_schedules.count }.by(1)

    within("turbo-frame#pay_schedules_section") do
      expect(page).to have_content("Acme Payroll")
      expect(page).to have_content("$2,500.00")
    end
  end
end
