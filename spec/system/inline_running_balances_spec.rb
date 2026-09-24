require "rails_helper"

RSpec.describe "Inline running balances", type: :system, js: true do
  after { page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") }

  it "starts September from a 200 opening report before applying the first day's transactions" do
    user = create(:user)
    account = create(:account, user: user, kind: :checking)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 9, 1))
    prior = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    create(:account_snapshot, account: account, recorded_on: Date.new(2026, 3, 28), balance: 4993.27)
    create(:expense_entry, budget_month: prior, source_account: account, section: :income, planned_amount: 1451)
    report = create(:account_snapshot, account: account, recorded_on: month.month_on, balance: 200)
    paycheck = create(:expense_entry, budget_month: month, source_account: account, section: :income,
      status: :paid, planned_amount: 2600, actual_amount: 2600)
    bill = create(:expense_entry, budget_month: month, source_account: account, status: :paid,
      planned_amount: 107.41, actual_amount: 107.41)

    sign_in_as(user)
    visit edit_account_account_snapshot_path(account, report)
    expect(page).to have_field("Balance date", with: "2026-09-01")
    select "Opening (before transactions)", from: "Balance timing"
    click_button "Update Balance"
    expect(page).to have_content("Balance snapshot updated.")
    expect(report.reload.recorded_on).to eq(Date.new(2026, 8, 31))

    visit budget_month_path(month)
    click_button "Show balances"
    expect(page).to have_css("#expense_entry_#{paycheck.id} [data-running-balance]", text: "$2,800.00")
    expect(page).to have_css("#expense_entry_#{bill.id} [data-running-balance]", text: "$2,692.59")
    expect(page).to have_no_content("$9,044.27")
  end

  it "shows and hides the column in place, preserves filters, and refreshes after a regular edit" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 9, 1), label: "September 2026")
    account = create(:account, user: user, name: "Everyday Checking", kind: :checking)
    savings = create(:account, user: user, name: "Rainy Day Savings", kind: :savings)
    create(:account_snapshot, account: account, recorded_on: month.month_on.prev_day, balance: 1000)
    create(:account_snapshot, account: savings, recorded_on: month.month_on.prev_day, balance: 500)
    income = create(:expense_entry, budget_month: month, source_account: account, section: :income, category: "Salary", payee: "Paycheck", planned_amount: 1500)
    bill = create(:expense_entry, budget_month: month, source_account: account, occurred_on: month.month_on + 4.days, payee: "Rent", planned_amount: 2600)
    create(:expense_entry, budget_month: month, source_account: savings, payee: "Savings fee", planned_amount: 10)

    sign_in_as(user)
    visit budget_month_path(month)
    within("#timeline_section") do
      expect(page).to have_no_css("th", text: /Balance after/i)
      select "Everyday Checking (2)", from: "Money leaves"
      click_button "Show balances"
      expect(page).to have_css("th", text: /Balance after/i)
      expect(page).to have_css("#expense_entry_#{income.id} [data-running-balance]", text: "$2,500.00")
      expect(page).to have_css("#expense_entry_#{bill.id} [data-running-balance]", text: "-$100.00")
      expect(page).to have_no_content("Savings fee")
      fill_in "Filter payee", with: "Rent"
      expect(page).to have_no_css("#expense_entry_#{income.id}")
      expect(page).to have_css("#expense_entry_#{bill.id} [data-running-balance]", text: "-$100.00")
      click_button "Hide balances"
      expect(page).to have_no_css("th", text: /Balance after/i)
      click_button "Show balances"
      find("#expense_entry_#{bill.id} a[aria-label='Edit entry']").click
    end
    within("#entry_editor_modal") do
      find("input[name='expense_entry[planned_amount]']").fill_in with: "2000"
      click_button "Update Entry"
    end
    within("#timeline_section") do
      expect(page).to have_button("Hide balances", wait: 10)
      expect(page).to have_css("#expense_entry_#{bill.id} [data-running-balance]", text: "$500.00")
      expect(page).to have_no_css("#expense_entry_#{income.id}")
      click_button "Clear filters"
      expect(page).to have_no_css("thead button")
      expect(page).to have_css("#expense_entry_#{income.id} [data-running-balance]", text: "$2,500.00")
    end
    page.execute_script("document.querySelector('.ta-toast-stack')?.remove()")
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    expect(page).to have_button("Hide balances")
    overflow = page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
    expect(overflow).to be <= 1
    expect(page).to have_css("#expense_entry_#{bill.id} [data-running-balance]", text: "$500.00", visible: :all)
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    if ENV["BALANCE_SCREENSHOT"]
      page.driver.browser.manage.window.resize_to(1440, 1200)
      page.save_screenshot(ENV.fetch("BALANCE_SCREENSHOT"))
    end
  end
end
