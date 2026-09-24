require "rails_helper"

RSpec.describe "Focused accounts navigation", type: :system, js: true do
  include ActiveJob::TestHelper
  it "keeps balances visible and reveals history, settings, and imports at the point of use" do
    user = create(:user)
    savings = create(:account, user: user, name: "Emergency savings", institution_name: "Community Bank", kind: :savings)
    card = create(:account, user: user, name: "Travel card", institution_name: "Demo Bank", kind: :credit_card)
    create(:account_snapshot, account: savings, balance: 12500, recorded_on: 2.days.ago.to_date)
    create(:account_snapshot, account: card, balance: -500, recorded_on: 2.days.ago.to_date)
    sign_in_as(user)

    visit accounts_path
    click_button "Mark as read" if page.has_button?("Mark as read", wait: 0)
    expect(page).to have_css("#accounts-summary", text: "$12,000.00")
    expect(page).to have_css("#tracked_accounts", text: "Travel card")
    expect(page).to have_css("#net-worth-history:not([open])")
    expect(page).to have_css("#account-balance-help:not([open])")
    expect(page).not_to have_content("Manual tracking")
    save_stable_screenshot("accounts-overview-desktop")

    find("#net-worth-history > summary").click
    expect(page).to have_css("#net-worth-history canvas", visible: true)
    find("summary", text: "Review exact net worth history").click
    expect(page).to have_css("#net-worth-history table", visible: true)
    find("#net-worth-history > summary").click

    within("#account_#{card.id}") { click_link "Travel card" }
    expect(page).to have_css("section[aria-label='Account balances']", text: "-$500.00")
    expect(page).to have_content("Recent activity")
    expect(page).to have_css("#account-movement:not([open])")
    expect(page).to have_css("#balance-calculation:not([open])")
    expect(page).to have_link("Record balance")
    expect(page).not_to have_link("Import activity")
    save_stable_screenshot("account-detail-desktop")

    click_link "Record balance"
    fill_in "Balance", with: "-525"
    click_button "Record Balance"
    expect(page).to have_current_path(account_path(card, view: "manage"))
    expect(page).to have_content("Balance snapshot recorded.")
    expect(page).to have_css("#manual-snapshots[open]", text: "-$525.00")
    click_link "Overview"

    find("#balance-calculation > summary").click
    expect(page).to have_content("Starting balance")
    click_link "Review balance sources"
    expect(page).to have_content("Account settings")
    expect(page).to have_css("#manual-snapshots:not([open])")
    expect(page).not_to have_field("Balance")
    find("summary", text: "Record a manual balance").click
    expect(page).to have_field("Balance")
    expect(page).not_to have_field("Available balance")
    find("summary", text: "Available balance and notes").click
    expect(page).to have_field("Available balance")

    within(".ta-content-header") do
      find("summary[aria-label='Actions for Travel card']").click
      click_link "Edit account"
    end
    fill_in "Institution", with: "Travel Bank"
    click_button "Update Account"
    expect(page).to have_content("Travel Bank")
    within(".ta-content-header") do
      find("summary[aria-label='Actions for Travel card']").click
      click_link "Import activity"
    end
    expect(page).to have_field("Institution CSV export", visible: true)
    expect(page).not_to have_content("No account files imported yet")
    attach_file "Institution CSV export", Rails.root.join("test/fixtures/files/account_activity/preamble_card_activity.csv")
    click_button "Preview Institution Activity"
    expect(page).to have_current_path(preview_account_account_activity_imports_path(card))
    expect(page).to have_css("h1", text: "Activity Import Preview")
    expect(page).to have_content("No account activity rows have been saved yet")
    click_button "Import Activity"
    expect(page).to have_content("Activity import queued")
    perform_enqueued_jobs(only: Accounts::ActivityImports::CommitJob)
    page.refresh
    expect(page).to have_content("Import complete")
    expect(card.account_activities.count).to be_positive

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    visit accounts_path
    expect(page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")).to be <= 1
    expect(page).to have_css("#mobile_account_#{card.id}")
    save_stable_screenshot("accounts-overview-mobile")
    within("#mobile_account_#{card.id}") { click_link "Travel card" }
    expect(page).to have_css("section[aria-label='Account balances']")
    expect(page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")).to be <= 1
    save_stable_screenshot("account-detail-mobile")
    find("#account-movement > summary").click
    expect(page).to have_css("#account-movement canvas", visible: true)
    expect(page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")).to be <= 1
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  def save_stable_screenshot(name)
    page.evaluate_async_script(<<~JS)
      const done = arguments[0];
      requestAnimationFrame(() => requestAnimationFrame(() => {
        Promise.all(document.getAnimations().map(animation => animation.finished.catch(() => {}))).then(done);
      }));
    JS
    page.save_screenshot(Rails.root.join("tmp/screenshots/#{name}.png"))
  end
end
