require "rails_helper"

RSpec.describe "Budget month management", type: :system do
  it "allows a signed in user to create a budget month" do
    user = create(:user, email: "planner@example.com")

    sign_in_as(user)
    visit new_budget_month_path

    fill_in "Month", with: "2026-05-01"
    fill_in "Label", with: "May 2026"
    fill_in "Planned income", with: "7200"
    click_button "Create"

    expect(page).to have_content("Budget month created.")
    expect(page).to have_content("May 2026")
  end

  it "shows the wizard choices on the new month page" do
    user = create(:user, email: "wizard@example.com")

    sign_in_as(user)
    visit new_budget_month_path

    expect(page).to have_content("How do you want to create this month?")
    expect(page).to have_field("Clone an existing month", type: "radio")
    expect(page).to have_field("Start fresh", type: "radio")
  end

  it "shows the clone preview when a source month is preselected" do
    user = create(:user, email: "preview@example.com")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    create(:expense_entry, budget_month: month, user: user, payee: "Rent", planned_amount: 1200)

    sign_in_as(user)
    visit new_budget_month_path(source_month_id: month.id)

    expect(page).to have_content("Success preview")
    expect(page).to have_content("April 2026")
    expect(page).to have_content("1 entries")
  end

  it "shows the split dashboard upload card" do
    user = create(:user, email: "dashboard@example.com")

    sign_in_as(user)
    visit root_path

    expect(page).to have_content("Existing months")
    expect(page).to have_content("Quick import")
    expect(page).to have_content("Drop a CSV here")
  end

  it "shows a help and documentation page from the sidebar" do
    user = create(:user, email: "help@example.com")

    sign_in_as(user)
    visit root_path

    click_link "Help & Documentation"

    expect(page).to have_content("Help & Documentation")
    expect(page).to have_content("A guided overview of what each part of the app does")
    expect(page).to have_content("Creating and cloning months")
    expect(page).to have_content("Planning templates")
    expect(page).to have_content("Reviewing a month")
  end

  it "hides generation actions when a past month looks complete" do
    user = create(:user, email: "complete@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.prev_month.beginning_of_month, label: Date.current.prev_month.strftime("%B %Y"))
    create(:expense_entry, budget_month: month, user: user, status: :paid, section: :fixed, payee: "Rent", planned_amount: 1500, actual_amount: 1500)

    sign_in_as(user)
    visit budget_month_path(month)

    expect(page).to have_content("looks complete")
    expect(page).not_to have_content("Add from planning templates")
    expect(page).not_to have_button("Add Paychecks")
    expect(page).not_to have_button("Add Subscriptions")
    expect(page).not_to have_button("Add Monthly Bills")
    expect(page).not_to have_button("Add Payment Plans")
    expect(page).not_to have_button("Estimate Card Payments")
  end

  it "renames the card estimate action for active months" do
    user = create(:user, email: "active@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))

    sign_in_as(user)
    visit budget_month_path(month)

    expect(page).to have_content("Add from planning templates")
    expect(page).to have_button("Estimate Card Payments")
  end

  it "shows reason pills from the month data" do
    user = create(:user, email: "reasons@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry, budget_month: month, user: user, category: "Groceries", payee: "Market", section: :variable, status: :planned, planned_amount: 120)
    create(:expense_entry, budget_month: month, user: user, category: "Fuel", payee: "Gas", section: :auto, status: :planned, planned_amount: 60)

    sign_in_as(user)
    visit budget_month_path(month)

    expect(page).to have_button("Groceries 1")
    expect(page).to have_button("Fuel 1")
  end

  it "allows a signed in user to sign out" do
    user = create(:user, email: "signout@example.com")

    sign_in_as(user)
    click_button "Sign out"

    expect(page).to have_content("Signed out successfully")
    expect(page).to have_content("Create account")
  end
end
