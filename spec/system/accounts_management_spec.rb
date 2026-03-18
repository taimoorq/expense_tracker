require "rails_helper"

RSpec.describe "Accounts management", type: :system do
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

    fill_in "Balance", with: "8500.25"
    click_button "Record Balance"

    expect(page).to have_content("Balance snapshot recorded.")
    expect(page).to have_content("$8,500.25")
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
    expect(page).to have_content("Paid linked entries are included after snapshots.")
    expect(page).to have_content("Latest updated")
    expect(page).to have_content("March 01, 2026")
    expect(page).to have_css("canvas[data-controller='chart']", visible: :all)
  end

  it "lets a signed in user edit and delete balance snapshots" do
    user = create(:user)
    account = create(:account, user: user, name: "Savings")
    snapshot = create(:account_snapshot, account: account, recorded_on: Date.new(2026, 3, 1), balance: 1200, notes: "Starting point")

    sign_in_as(user)
    visit account_path(account)

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
    expect(page).to have_content("No snapshots yet")
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

    expect(page).to have_content("Account activity and connections")
    expect(page).to have_button("Activity")
    expect(page).to have_button("Connected Templates")
    expect(page).to have_content("Acme Payroll")
    expect(page).to have_content("Net impact")
  end
end
