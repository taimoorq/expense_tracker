require "rails_helper"

RSpec.describe "Budget month management", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    travel_to Time.zone.local(2026, 3, 15, 12, 0, 0) do
      example.run
    end
  end

  it "allows a signed in user to create a budget month" do
    user = create(:user, email: "planner@example.com")

    sign_in_as(user)
    visit new_budget_month_path

    fill_in "Month", with: "2026-05-01"
    fill_in "Label", with: "May 2026"
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
    visit budget_months_path

    expect(page).to have_content("Existing months")
    expect(page).to have_content("Quick import")
    expect(page).to have_content("Drop a CSV here")
  end

  it "shows only the current year's months by default and filters older years" do
    user = create(:user, email: "yearfilter@example.com")
    create(:budget_month, user: user, month_on: Date.new(2026, 1, 1), label: "January 2026")
    create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    create(:budget_month, user: user, month_on: Date.new(2026, 4, 1), label: "April 2026")
    create(:budget_month, user: user, month_on: Date.new(2025, 12, 1), label: "December 2025")

    sign_in_as(user)
    visit budget_months_path

    month_labels = within("#existing-months tbody") do
      all("tr td:first-child a", minimum: 3).map(&:text)
    end

    expect(page).to have_content("3 months in 2026")
    expect(page).to have_content("March 2026")
    expect(page).to have_content("January 2026")
    expect(month_labels).to include("March 2026", "April 2026", "January 2026")
    expect(month_labels.index("March 2026")).to be < month_labels.index("April 2026")
    expect(page).not_to have_content("December 2025")
    expect(page).to have_link("2025")

    click_link "2025"

    expect(page).to have_content("1 month in 2025")
    expect(page).to have_content("December 2025")
    expect(page).not_to have_content("March 2026")

    click_link "2026"

    expect(page).to have_content("3 months in 2026")
    expect(page).to have_content("March 2026")
    expect(page).not_to have_content("December 2025")
  end

  it "keeps the months list in a scrollable box" do
    user = create(:user, email: "scrollmonths@example.com")

    sign_in_as(user)
    visit budget_months_path

    expect(page).to have_css('[data-month-list="scrollable"][style*="max-height: 26rem"]', visible: :all)
  end

  it "shows a planning template overview on the months page" do
    user = create(:user, email: "templateoverview@example.com")
    create(:pay_schedule, user: user, name: "Main Job")
    create(:subscription, user: user, name: "Netflix")
    create(:monthly_bill, user: user, name: "Mortgage")
    create(:payment_plan, user: user, name: "IRS")
    create(:credit_card, user: user, name: "Visa")

    sign_in_as(user)
    visit budget_months_path

    expect(page).to have_content("Planning templates")
    expect(page).to have_content("5 total")
    expect(page).to have_link("Pay schedules")
    expect(page).to have_link("Monthly bills")
    expect(page).to have_link("Manage Planning Templates")
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
    expect(page).to have_content("Add accounts first")
    expect(page).to have_link("Set up Accounts")
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
    expect(page).to have_content("Build the month from templates")
    expect(page).to have_button("Estimate Card Payments")
  end

  it "keeps add monthly bills available until all saved bill templates are represented", js: true do
    user = create(:user, email: "monthlybillcoverage@example.com")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    create(:monthly_bill, user: user, name: "Mortgage", due_day: 12, default_amount: 1800, kind: :fixed_payment)
    create(:monthly_bill, user: user, name: "Electric", due_day: 18, default_amount: 140, kind: :variable_bill)
    create(:expense_entry,
      budget_month: month,
      user: user,
      source_file: "March 2026 Transactions.csv",
      occurred_on: Date.new(2026, 3, 12),
      section: :fixed,
      category: "Housing",
      payee: "Mortgage",
      planned_amount: 1800,
      actual_amount: 1800,
      account: "Checking",
      status: :paid)

    sign_in_as(user)
    visit budget_month_path(month)

    click_button "Plan and Edit"

    expect(page).to have_button("Add Monthly Bills")
    expect(page).to have_text(/1 of 2 templates represented/i)

    click_button "Add Monthly Bills"

    expect(page).to have_content("Generated 1 monthly bill entry.")
    expect(page).to have_text(/2 of 2 templates represented/i)
    expect(page).not_to have_button("Add Monthly Bills")
  end

  it "opens planning templates from the plan and edit panel", js: true do
    user = create(:user, email: "planedittemplates@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))

    sign_in_as(user)
    visit budget_month_path(month)

    click_button "Plan and Edit"
    click_link "Open Planning Templates"

    expect(page).to have_current_path(planning_templates_path)
    expect(page).to have_content("Planning Templates")
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


  it "filters timeline by category dropdown", js: true do
    user = create(:user, email: "categoryfilter@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry, budget_month: month, user: user, payee: "Market", category: "Groceries", section: :variable, status: :planned, planned_amount: 100)
    create(:expense_entry, budget_month: month, user: user, payee: "Gas", category: "Fuel", section: :auto, status: :planned, planned_amount: 50)

    sign_in_as(user)
    visit budget_month_path(month)

    expect(page).to have_select("timeline_category_filter", with_options: [ "Groceries (1)", "Fuel (1)" ])
    select "Groceries (1)", from: "timeline_category_filter"
    expect(page).to have_text("Market")
    expect(page).not_to have_text("Gas")
  end

  it "filters calendar by category dropdown", js: true do
    user = create(:user, email: "calendarcategoryfilter@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry, budget_month: month, user: user, payee: "Market", category: "Groceries", section: :variable, status: :planned, planned_amount: 100, occurred_on: Date.current.beginning_of_month + 5.days)
    create(:expense_entry, budget_month: month, user: user, payee: "Gas", category: "Fuel", section: :auto, status: :planned, planned_amount: 50, occurred_on: Date.current.beginning_of_month + 10.days)

    sign_in_as(user)
    visit budget_month_path(month)
    click_button "Calendar", match: :first

    expect(page).to have_select("timeline_category_filter", with_options: [ "Groceries (1)", "Fuel (1)" ])
    select "Groceries (1)", from: "timeline_category_filter"
    expect(page).to have_text("Market")
    expect(page).not_to have_text("Gas")
  end

  it "persists filter state when switching between timeline and calendar toggles", js: true do
    user = create(:user, email: "filterpersist@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry, budget_month: month, user: user, payee: "Market", category: "Groceries", section: :variable, status: :planned, planned_amount: 100, occurred_on: Date.current.beginning_of_month + 5.days)
    create(:expense_entry, budget_month: month, user: user, payee: "Gas", category: "Fuel", section: :auto, status: :planned, planned_amount: 50, occurred_on: Date.current.beginning_of_month + 10.days)

    sign_in_as(user)
    visit budget_month_path(month)

    select "Groceries (1)", from: "timeline_category_filter"
    expect(page).to have_text("Market")
    expect(page).not_to have_text("Gas")

    click_button "Calendar", match: :first
    expect(page).to have_select("timeline_category_filter", selected: "Groceries (1)")
    expect(page).to have_text("Market")
    expect(page).not_to have_text("Gas")
  end

  it "expands matching timeline groups while filters are active", js: true do
    user = create(:user, email: "timelinefilters@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry, budget_month: month, user: user, payee: "Payroll", category: "Paycheck", section: :income, status: :planned, planned_amount: 2500)
    create(:expense_entry, budget_month: month, user: user, payee: "Netflix", category: "Subscription", section: :fixed, status: :planned, planned_amount: 19.99, source_file: "subscription")

    sign_in_as(user)
    visit budget_month_path(month)

    open_state = -> { page.evaluate_script("document.querySelector(\"details[data-group-id='recurring-subscriptions']\")?.open") }

    expect(page).to have_css("details[data-group-id='recurring-subscriptions']", visible: :all)
    expect(open_state.call).to be(false)

    fill_in "Filter payee", with: "Netflix"

    expect(page).to have_text("Netflix")
    expect(open_state.call).to be(true)

    fill_in "Filter payee", with: ""

    expect(open_state.call).to be(false)
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

    expect(page).to have_content("Budget")
    expect(page).to have_button("Mark as paid", visible: :all)
    expect(page).to have_css("[data-collapsible-groups-storage-key-value='timeline-groups-#{month.id}']")
  end

  it "can switch the timeline between section view and full list view", js: true do
    user = create(:user, email: "timelineviewtoggle@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry, budget_month: month, user: user, payee: "Phone", category: "Utilities", planned_amount: 45.10, actual_amount: nil, status: :planned)

    sign_in_as(user)
    visit budget_month_path(month)

    expect(page).to have_button("Grouped")
    expect(page).to have_button("Full List")
    expect(page).to have_content("Other")
    expect(page).to have_button("Expand all")
    expect(page).to have_button("Collapse all")

    click_button "Full List"

    expect(page).to have_content("Phone")
    expect(page).to have_content("Utilities")
    expect(page).to have_text(/actual/i)
    expect(page).not_to have_button("Expand all")
    expect(page).not_to have_button("Collapse all")

    click_button "Grouped"

    expect(page).to have_content("Budget")
    expect(page).to have_button("Expand all")
  end

  it "opens the guided wizard from the timeline", js: true do
    user = create(:user, email: "timelinewizard@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry, budget_month: month, user: user, payee: "Phone", planned_amount: 45.10, actual_amount: nil, status: :planned)

    sign_in_as(user)
    visit budget_month_path(month)

    click_link "Add Entry with Wizard"

    expect(page).to have_content("Add Entry with Wizard")
    expect(page).to have_css("turbo-frame#entry_wizard_modal")
  end

  it "opens the guided wizard from the calendar view", js: true do
    user = create(:user, email: "calendarwizard@example.com")
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry, budget_month: month, user: user, payee: "Phone", planned_amount: 45.10, actual_amount: nil, status: :planned, occurred_on: Date.current.beginning_of_month + 2.days)

    sign_in_as(user)
    visit budget_month_path(month)

    click_button "Calendar", match: :first
    click_link "Add Entry with Wizard"

    expect(page).to have_content("Add Entry with Wizard")
    expect(page).to have_css("turbo-frame#entry_wizard_modal")
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

      it "recognizes imported entries that already match templates" do
        user = create(:user, email: "importedmatches@example.com")
        month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

        create(:pay_schedule,
          user: user,
          name: "Employer",
          cadence: :semimonthly,
          amount: 4200,
          first_pay_on: Date.new(2026, 3, 7),
          day_of_month_one: 7,
          day_of_month_two: 22,
          weekend_adjustment: :no_adjustment,
          active: true)
        create(:subscription, user: user, name: "Netflix", amount: 21.19, due_day: 19, account: "Card", active: true)
        create(:monthly_bill, user: user, name: "Mortgage", kind: :fixed_payment, due_day: 31, account: "Checking", active: true)
        create(:payment_plan, user: user, name: "Apple Financing", total_due: 1200, amount_paid: 300, monthly_target: 107.41, due_day: 15, account: "Card", active: true)
        create(:credit_card, user: user, name: "Chase", minimum_payment: 50, priority: 1, active: true)

        create(:expense_entry,
          budget_month: month,
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
          budget_month: month,
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
          budget_month: month,
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
          budget_month: month,
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
        create(:expense_entry,
          budget_month: month,
          user: user,
          source_file: "March 2026 Transactions.csv",
          occurred_on: Date.new(2026, 3, 31),
          section: :debt,
          category: "Credit Card",
          payee: "Chase",
          planned_amount: 250,
          account: "Checking",
          status: :planned)

        sign_in_as(user)
        visit budget_month_path(month)

        expect(page).to have_content("Paycheck entries are already in this month.")
        expect(page).to have_content("Subscription entries are already in this month.")
        expect(page).to have_content("Monthly bill entries are already in this month.")
        expect(page).to have_content("Payment-plan entries are already in this month.")
        expect(page).to have_button("Re-estimate Card Payments")
        expect(page).not_to have_button("Add Paychecks")
        expect(page).not_to have_button("Add Subscriptions")
        expect(page).not_to have_button("Add Monthly Bills")
        expect(page).not_to have_button("Add Payment Plans")
      end

  it "allows a signed in user to sign out" do
    user = create(:user, email: "signout@example.com")

    sign_in_as(user)
    visit root_path

    first("button[aria-label='Open account menu']").click
    click_button "Sign out", match: :first

    expect(page).to have_content("Signed out successfully")
    expect(page).to have_content("Create account")
  end

  it "links to the accounts area from the signed in navigation" do
    user = create(:user)

    sign_in_as(user)
    visit root_path

    click_link "Accounts & Net Worth"

    expect(page).to have_content("Track savings, investment, cash, and debt balances manually alongside your monthly budget.")
  end
end
