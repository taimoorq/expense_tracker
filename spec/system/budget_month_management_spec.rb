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

  it "defaults empty active months to the plan and edit tab" do
    user = create(:user, email: "active@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))

    sign_in_as(user)
    visit budget_month_path(month)

    expect(page).to have_css('section[data-controller="tabs"][data-tabs-default-tab-value="entries"]')
    expect(page).to have_button("Plan and Edit")
    expect(page).to have_content("Plan and Edit This Month")
    expect(page).to have_content("Add from planning templates")
    expect(page).to have_button("Estimate Card Payments")
  end

  it "shows a separate breakdown tab for the visual charts" do
    user = create(:user, email: "breakdown@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry, budget_month: month, user: user, category: "Groceries", payee: "Market", section: :variable, status: :planned, planned_amount: 120)

    sign_in_as(user)
    visit budget_month_path(month)

    expect(page).to have_button("Breakdown")
    expect(page).to have_css('[data-panel-name="breakdown"]')
    expect(page).to have_content("Visual Budget Breakdown")
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

  it "lets a user mark an entry as paid from the edit page" do
    user = create(:user, email: "paid@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    entry = create(:expense_entry, budget_month: month, user: user, payee: "Water", planned_amount: 88.45, actual_amount: nil, status: :planned)

    sign_in_as(user)
    visit edit_budget_month_expense_entry_path(month, entry)

    expect(page).to have_button("Mark as Paid")

    click_button "Mark as Paid"

    expect(page).to have_content("Entry updated.")
    expect(entry.reload.status).to eq("paid")
    expect(entry.actual_amount.to_d).to eq(88.45.to_d)
  end

  it "renders a mark as paid action in entry rows" do
    user = create(:user, email: "rowpaid@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry, budget_month: month, user: user, payee: "Internet", planned_amount: 65.25, actual_amount: nil, status: :planned)

    sign_in_as(user)
    visit budget_month_path(month)

    expect(page).to have_button("Mark as paid", visible: :all)
  end

  it "renders a mark as paid action in timeline rows" do
    user = create(:user, email: "timelinepaid@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry, budget_month: month, user: user, payee: "Phone", planned_amount: 45.10, actual_amount: nil, status: :planned)

    sign_in_as(user)
    visit budget_month_path(month)

    expect(page).to have_content("Month Timeline")
    expect(page).to have_button("Mark as paid", visible: :all)
    expect(page).to have_css("[data-collapsible-groups-storage-key-value='timeline-groups-#{month.id}']")
  end

  it "shows payment sections above recurring subscriptions and highlights editable payment rows" do
    user = create(:user, email: "paymentsections@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry, budget_month: month, user: user, payee: "Netflix", category: "Subscription", section: :fixed, status: :planned, planned_amount: 20, source_file: "subscription")
    create(:expense_entry, budget_month: month, user: user, payee: "IRS Plan", category: "Payment Plan", section: :debt, status: :planned, planned_amount: 100, source_file: "payment_plan")
    create(:expense_entry, budget_month: month, user: user, payee: "Visa", category: "Credit Card", section: :debt, status: :planned, planned_amount: 75, source_file: "credit_card_estimate")

    sign_in_as(user)
    visit budget_month_path(month)

    body = page.body
    expect(body.index("Payment Plans")).to be < body.index("Recurring Subscriptions")
    expect(body.index("Credit Card Payments")).to be < body.index("Recurring Subscriptions")
    expect(page).to have_content("Amount/date may change month to month.")
    expect(page).to have_content("Actual not set")
  end

  it "allows a signed in user to sign out" do
    user = create(:user, email: "signout@example.com")

    sign_in_as(user)
    click_button "Sign out"

    expect(page).to have_content("Signed out successfully")
    expect(page).to have_content("Create account")
  end
end
