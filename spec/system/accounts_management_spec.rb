require "rails_helper"

RSpec.describe "Accounts management", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  it "lets a signed in user create an account with an initial balance snapshot" do
    user = create(:user)

    sign_in_as(user)
    visit new_account_path

    fill_in "Name", with: "Brokerage"
    fill_in "Institution", with: "Vanguard"
    select "Brokerage", from: "Account type"
    fill_in "Balance", with: "15250.75"
    fill_in "Available balance", with: "800.25"
    fill_in "Opening balance notes", with: "Opening balance"
    click_button "Create Account"

    expect(page).to have_content("Account created and initial balance recorded.")
    expect(page).to have_content("$15,250.75")
    click_link "Manage"
    expect(page).to have_content("$800.25")
    expect(page).to have_content("Opening balance")
  end

  it "lets a signed in user create an account and record a balance snapshot" do
    user = create(:user)

    sign_in_as(user)
    visit accounts_path

    click_link "New Account"

    fill_in "Name", with: "Emergency Savings"
    fill_in "Institution", with: "Ally"
    select "Savings", from: "Account type"
    check "Include in net worth"
    check "Include in cash totals"
    click_button "Create Account"

    expect(page).to have_content("Account created. Add a balance snapshot to start tracking it.")
    expect(page).to have_content("Emergency Savings")

    click_link "Manage"
    fill_in "Balance", with: "8500.25"
    click_button "Record Balance"

    expect(page).to have_content("Balance snapshot recorded.")
    expect(page).to have_content("$8,500.25")
  end

  it "lets a signed in user schedule a monthly payment while creating a credit card account", js: true do
    user = create(:user)
    create(:account, user: user, name: "Checking", kind: :checking, include_in_cash: true)

    sign_in_as(user)
    visit new_account_path

    fill_in "Name", with: "Visa Rewards"
    fill_in "Institution", with: "Chase"
    select "Credit card", from: "Account type"
    check "Schedule monthly payment"
    select "Checking", from: "Money leaves account"
    fill_in "Monthly payment amount", with: "85.00"
    fill_in "Due day", with: "18"
    fill_in "Priority", with: "2"
    click_button "Create Account"

    expect(page).to have_content("Account created and card payment scheduled.")
    expect(page).to have_content("Visa Rewards")

    click_link "Manage"

    expect(page).to have_content("Connected recurring templates")
    expect(page).to have_content("Visa Rewards")
    expect(user.credit_cards.find_by!(name: "Visa Rewards").payment_account.name).to eq("Checking")
  end

  it "shows latest balances in the accounts net worth summary" do
    user = create(:user)
    savings = create(:account, user: user, name: "Savings", kind: :savings)
    card = create(:account, user: user, name: "Credit Card", kind: :credit_card)
    create(:account_snapshot, account: savings, recorded_on: Date.new(2026, 3, 1), balance: 10000)
    create(:account_snapshot, account: card, recorded_on: Date.new(2026, 3, 1), balance: -2500)

    sign_in_as(user)
    visit accounts_path

    expect(page).to have_content("Assets")
    expect(page).to have_content("Liabilities")
    expect(page).to have_content("Net Worth")
    expect(page).to have_content("$10,000.00")
    expect(page).to have_content("$2,500.00")
    expect(page).to have_content("$7,500.00")
    expect(page).to have_content("Imports and paid linked entries are reflected from their trusted sources.")
    expect(page).to have_content("Latest updated")
    expect(page).to have_content("Latest trusted source")
    expect(page).to have_content("March 01, 2026")
    expect(page).to have_css("canvas[data-controller='chart']", visible: :all)
  end

  it "lets a signed in user edit and delete balance snapshots" do
    user = create(:user)
    account = create(:account, user: user, name: "Savings")
    snapshot = create(:account_snapshot, account: account, recorded_on: Date.new(2026, 3, 1), balance: 1200, notes: "Starting point")

    sign_in_as(user)
    visit account_path(account)
    click_link "Manage"

    within("tr", text: "Starting point") do
      click_link "Edit"
    end

    fill_in "Balance", with: "1800"
    fill_in "Notes", with: "Corrected balance"
    click_button "Update Balance"

    expect(page).to have_content("Balance snapshot updated.")
    expect(page).to have_content("$1,800.00")
    expect(page).to have_content("Corrected balance")

    within("tr", text: "Corrected balance") do
      click_button "Delete"
    end

    expect(page).to have_content("Balance snapshot deleted.")
    expect(page).to have_content("No manual snapshots yet")
    expect { snapshot.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "shows linked entry activity and connected templates on the account page" do
    user = create(:user)
    account = create(:account, user: user, name: "Checking")
    schedule = create(:pay_schedule, user: user, name: "Acme Payroll", linked_account: account, account: "Checking")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    create(
      :expense_entry,
      budget_month: month,
      user: user,
      section: :income,
      payee: "Acme Payroll",
      category: "Paycheck",
      planned_amount: 3200,
      actual_amount: 3200,
      status: :paid,
      source_file: "pay_schedule",
      source_template: schedule,
      source_account: account,
      account: "Checking"
    )

    sign_in_as(user)
    visit account_path(account)

    expect(page).to have_link("Activity")
    click_link "Activity"
    expect(page).to have_content("Budget-linked activity")
    expect(page).to have_content("Acme Payroll")
    expect(page).to have_content("Net +$3,200.00")

    click_link "Manage"
    expect(page).to have_content("Connected recurring templates")
    expect(page).to have_content("How balance is calculated")
    expect(page).to have_content("Acme Payroll")
    expect(page).to have_link("Edit account", href: edit_account_path(account))
    expect(page).to have_no_link("Back to Accounts")
  end

  it "shows credit card payoff progress on credit card account pages" do
    travel_to Time.zone.local(2026, 6, 15, 12, 0, 0) do
      user = create(:user)
      checking = create(:account, user: user, name: "Checking", kind: :checking)
      card = create(:account, user: user, name: "Rewards Visa", kind: :credit_card)
      month = create(:budget_month, user: user, month_on: Date.new(2026, 6, 1), label: "June 2026")
      create(:account_snapshot, account: card, recorded_on: Date.new(2026, 6, 1), balance: -1_000)

      create(:expense_entry,
        budget_month: month,
        user: user,
        source_account: card,
        occurred_on: Date.new(2026, 6, 4),
        section: :variable,
        status: :paid,
        actual_amount: 125)

      create(:expense_entry,
        budget_month: month,
        user: user,
        source_account: checking,
        destination_account: card,
        occurred_on: Date.new(2026, 6, 10),
        section: :debt,
        status: :paid,
        actual_amount: 325)

      sign_in_as(user)
      visit account_path(card)

      expect(page).to have_content("Credit card payoff progress")
      expect(page).to have_content("Paid down this month")
      expect(page).to have_content("$325.00")
      expect(page).to have_content("Added this month")
      expect(page).to have_content("$125.00")
      expect(page).to have_content("Progress toward payoff")
      expect(page).to have_content("20%")
      expect(page).to have_content("$800.00 remains")
    end
  end

  it "follows a credit card charge story from the chart table to exact institution rows" do
    travel_to Time.zone.local(2026, 6, 15, 12, 0, 0) do
      user = create(:user)
      card = create(:account, user: user, name: "Rewards Card", kind: :credit_card)
      create(:account_snapshot, account: card, recorded_on: Date.new(2026, 6, 1), balance: -500)
      activity_import = create(:account_activity_import, account: card, started_on: Date.new(2026, 6, 1), ended_on: Date.new(2026, 6, 15))
      create(:account_activity, account: card, account_activity_import: activity_import, transaction_on: Date.new(2026, 6, 5), description: "CARD PURCHASE", account_delta: -125, amount: 125)
      create(:account_activity, account: card, account_activity_import: activity_import, transaction_on: Date.new(2026, 6, 10), description: "AUTOPAY PAYMENT", account_delta: 300, amount: 300)

      sign_in_as(user)
      visit account_path(card)

      expect(page).to have_content("Charges and payments over time")
      expect(page).to have_content("Payments & credits")
      expect(page).to have_css("canvas[data-controller='chart']", visible: :all)
      find("a[aria-label='Review charges for Jun 2026']").click

      expect(page).to have_content("Institution activity")
      expect(page).to have_content("CARD PURCHASE")
      expect(page).to have_no_content("AUTOPAY PAYMENT")
      expect(page).to have_content("Showing outgoing from institution activity")
    end
  end

  it "shows checking money in and money out without claiming every inflow is income" do
    travel_to Time.zone.local(2026, 6, 15, 12, 0, 0) do
      user = create(:user)
      checking = create(:account, user: user, name: "Checking", kind: :checking)
      activity_import = create(:account_activity_import, account: checking, started_on: Date.new(2026, 6, 1), ended_on: Date.new(2026, 6, 15))
      create(:account_activity, account: checking, account_activity_import: activity_import, transaction_on: Date.new(2026, 6, 3), description: "TRANSFER IN", account_delta: 1_000, amount: 1_000)
      create(:account_activity, account: checking, account_activity_import: activity_import, transaction_on: Date.new(2026, 6, 8), description: "UTILITY PAYMENT", account_delta: -250, amount: 250)

      sign_in_as(user)
      visit account_path(checking)

      expect(page).to have_content("Money in and money out over time")
      expect(page).to have_content("Money in")
      expect(page).to have_content("Money out")
      expect(page).to have_no_content("Income over time")
    end
  end
end
