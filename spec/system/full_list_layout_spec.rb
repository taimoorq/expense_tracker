require "rails_helper"

RSpec.describe "Full List ledger filters", type: :system, js: true do
  after { page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") }

  it "filters the stacked row details and recovers from an empty result without changing balances" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 9, 1), label: "September 2026")
    checking = create(:account, user: user, name: "Everyday Checking", kind: :checking)
    savings = create(:account, user: user, name: "Rainy Day Savings", kind: :savings)
    create(:account_snapshot, account: checking, recorded_on: month.month_on.prev_day, balance: 200)
    create(:account_snapshot, account: savings, recorded_on: month.month_on.prev_day, balance: 500)
    [
      [ 1, "Northwind Payroll", "Paycheck", :income, :paid, 2600, 2600 ],
      [ 1, "Apple Card", "Credit card", :fixed, :paid, 107.41, 107.41 ],
      [ 4, "Auto loan", "Monthly payment", :fixed, :paid, 876.30, 876.30 ],
      [ 4, "Chase", "Credit card", :debt, :paid, 2897.38, 2000 ],
      [ 7, "Consulting Payroll", "Paycheck", :income, :planned, 4200, nil ],
      [ 7, "Neighborhood Community Association — quarterly maintenance", "Housing", :fixed, :planned, 450, nil ]
    ].each do |day, payee, category, section, status, planned, actual|
      create(:expense_entry, budget_month: month, source_account: checking, occurred_on: month.month_on.change(day: day),
        payee: payee, category: category, section: section, status: status, planned_amount: planned, actual_amount: actual)
    end
    create(:expense_entry, budget_month: month, source_account: savings, occurred_on: month.month_on.change(day: 9),
      payee: "Savings fee", category: "Fees", planned_amount: 10, status: :skipped)

    sign_in_as(user)
    visit budget_month_path(month)
    within("#timeline_section") do
      click_button "Show balances"
      select "Credit card (2)", from: "Category"
      expect(page).to have_css("[data-full-list-payee]", count: 2)
      expect(page).to have_css("[data-running-balance]", text: "-$183.71")
      click_button "Clear filters"
      select "Rainy Day Savings (1)", from: "Money leaves"
      expect(page).to have_css("[data-full-list-payee]", count: 1, text: "Savings fee")
      click_button "Clear filters"
      page.execute_script("arguments[0].value = '2026-09-04'; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", find_field("Date"))
      expect(page).to have_css("[data-full-list-payee]", count: 2)
      expect(page).to have_css("[data-full-list-payee]", text: "Auto loan")
      click_button "Clear filters"
      fill_in "Payee", with: "Payroll"
      expect(page).to have_css("[data-full-list-payee]", count: 2)
      click_button "Clear filters"
      fill_in "Reason", with: "monthly payment"
      expect(page).to have_css("[data-full-list-payee]", count: 1, text: "Auto loan")
      click_button "Clear filters"
      select "Planned", from: "Status"
      expect(page).to have_css("[data-full-list-payee]", count: 2)
      fill_in "Payee", with: "Chase"
      expect(page).to have_content("No entries match these filters.")
      expect(page).to have_no_css("[data-full-list-payee]")
      click_button "Clear filters"
      expect(page).to have_css("[data-full-list-payee]", count: 7)
      expect(page).to have_no_content("No entries match these filters.")
      expect(page).to have_css("[data-running-balance]", text: "-$183.71")
    end

    if ENV["FULL_LIST_SCREENSHOTS"]
      page.driver.browser.manage.window.resize_to(1600, 1600)
      settle_and_scroll_to_ledger
      find(".ta-full-list").native.save_screenshot("#{ENV.fetch('FULL_LIST_SCREENSHOTS')}-light.png")
      visit settings_path
      select "Midnight", from: "Color scheme"
      expect(page).to have_css("body.ta-theme-dark")
      visit budget_month_path(month)
      expect(page).to have_button("Hide balances")
      settle_and_scroll_to_ledger
      find(".ta-full-list").native.save_screenshot("#{ENV.fetch('FULL_LIST_SCREENSHOTS')}-dark.png")
      page.execute_script("document.querySelector('.ta-toast-stack')?.remove()")
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
      expect(page).to have_no_css("body.ta-shell-collapsed")
      settle_and_scroll_to_ledger
      expect(page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")).to be <= 1
      page.save_screenshot("#{ENV.fetch('FULL_LIST_SCREENSHOTS')}-mobile.png")
      page.execute_script("const table = document.querySelector('.ta-full-list').parentElement; table.scrollLeft = table.scrollWidth")
      page.save_screenshot("#{ENV.fetch('FULL_LIST_SCREENSHOTS')}-mobile-balances.png")
    end
  end

  def settle_and_scroll_to_ledger
    page.evaluate_async_script("const done = arguments[0]; Promise.all([document.fonts.ready, ...document.getAnimations().map(animation => animation.finished.catch(() => {}))]).then(done)")
    page.execute_script("window.scrollTo({ top: document.querySelector('.ta-full-list').getBoundingClientRect().top + window.scrollY - 90, behavior: 'instant' })")
  end
end
