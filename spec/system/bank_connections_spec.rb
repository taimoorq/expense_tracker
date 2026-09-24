require "rails_helper"

RSpec.describe "SimpleFIN account onboarding", type: :system, js: true do
  it "connects, polls discovered accounts, maps and accepts a balance, and retains it after disconnect" do
    user = create(:user)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.update!(target_reads_enabled: true, target_writes_enabled: true)
    client = instance_double(BankConnections::Simplefin::Client,
      claim: "https://demo:secret@beta-bridge.simplefin.org/simplefin",
      accounts: { "accounts" => [ { "id" => "demo-checking", "conn_id" => "demo-bank", "name" => "Everyday Checking", "currency" => "USD", "balance" => "3200.00", "balance-date" => 1.hour.ago.to_i } ] })
    allow(BankConnections::Simplefin::Client).to receive(:new).and_return(client)
    sign_in_as(user)
    visit accounts_path
    click_link "Bank connections"
    click_link "Connect SimpleFIN"
    fill_in "Setup Token", with: "demo-setup-token"
    click_button "Connect SimpleFIN"
    expect(page).to have_content("SimpleFIN connected")
    run = workspace.bank_refreshes.sole
    BankConnections::Refresh.new(refresh: run, client: client).call
    begin
      expect(page).to have_content("Everyday Checking", wait: 10)
    rescue RSpec::Expectations::ExpectationNotMetError
      page.save_page(Rails.root.join("tmp/simplefin-browser.html"))
      raise
    end
    click_button "Save mapping"
    expect(page).to have_content("Account mapping saved")
    find("summary", text: "Account connection settings").click
    expect(page).not_to have_field("New account name", visible: true)
    select "Create a new account", from: "Use existing account"
    expect(page).to have_field("New account name", visible: true)
    select "Everyday Checking", from: "Use existing account"
    expect(page).not_to have_field("New account name", visible: true)
    find("summary", text: "Account connection settings").click
    click_link "Review balance and recorded payments"
    check "I reviewed the balance and recorded activity above."
    click_button "Use this bank balance"
    visit accounts_path
    expect(page).to have_content("$3,200.00")
    expect(page).to have_content("BANK BALANCE")
    account = workspace.connected_accounts.sole.account
    within("#account_#{account.id}") do
      expect(page).to have_content("SimpleFIN")
      expect(page).not_to have_link("Review balance")
      find("summary[aria-label='Actions for Everyday Checking']").click
      click_link "Review bank balance"
    end
    expect(page).to have_content("Review bank balance")
    visit accounts_path
    find("#tracked_accounts").native.save_screenshot(Rails.root.join("tmp/screenshots/tracked-accounts-desktop.png"))
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    page.refresh
    expect(page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")).to be <= 1
    within("#mobile_account_#{account.id}") do
      expect(page).to have_content("SimpleFIN")
      expect(page).to have_content("BANK BALANCE")
      find("summary[aria-label='Actions for Everyday Checking']").click
      expect(page).to have_link("Review bank balance")
    end
    find("#tracked_accounts").native.save_screenshot(Rails.root.join("tmp/screenshots/tracked-accounts-mobile.png"))
    within("#mobile_account_#{account.id}") { click_link "Manage connection" }
    expect(page).to have_button("Refresh from SimpleFIN", disabled: false)
    find("summary", text: "Connection settings", exact_text: true).click
    click_button "Disconnect SimpleFIN"
    expect(page).to have_content("Disconnected. History was kept.")
    visit accounts_path
    expect(page).to have_content("Disconnected · showing saved history")
    expect(page).to have_content("$3,200.00")
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  it "keeps mixed account rows focused and makes secondary actions keyboard accessible on desktop and mobile" do
    user = create(:user)
    context = Identity::PersonalWorkspaceProvisioner.call(user: user)
    connection = create(:bank_connection, budget_workspace: context.workspace, actor_membership: context.membership)
    retirement = create(:workspace_account, user: user, budget_workspace: context.workspace, name: "Retirement savings", institution_name: "Fidelity", kind: :retirement)
    create(:account_snapshot, account: retirement, balance: 185420, recorded_on: Date.current - 5)
    savings = create(:connected_account, bank_connection: connection)
    savings.account.update!(name: "Advantage Savings · 2793", institution_name: "Bank of America", kind: :savings)
    create(:provider_balance, connected_account: savings, balance: 4850, reported_at: 1.hour.ago)
    card = create(:connected_account, bank_connection: connection, sign_multiplier: -1)
    card.account.update!(name: "Travel credit card", institution_name: "Barclays", kind: :credit_card, include_in_net_worth: false)
    create(:account_snapshot, account: card.account, balance: -620, recorded_on: Date.current - 3)
    create(:provider_balance, connected_account: card, balance: 578.39, reported_at: 3.days.ago)
    cash = create(:workspace_account, user: user, budget_workspace: context.workspace, name: "Cash envelope", institution_name: nil, kind: :cash)
    create(:account_snapshot, account: cash, balance: 0)
    missing = create(:connected_account, bank_connection: connection, state: "missing")
    missing.account.update!(name: "Everyday checking", institution_name: "Community Bank", kind: :checking)
    create(:provider_balance, connected_account: missing, balance: 241.38)

    sign_in_as(user)
    visit accounts_path
    within("#account_#{savings.account_id}") do
      expect(page).to have_content("Needs source")
      expect(page).to have_content("$4,850.00")
      expect(page).to have_link("Review balance")
      expect(page).not_to have_link("Edit account")
    end
    within("#account_#{card.account_id}") do
      expect(page).to have_content("-$578.39")
      expect(page).to have_content("Stale balance")
      expect(page).to have_content("Not in net worth")
    end
    within("#account_#{missing.account_id}") do
      expect(page).to have_link("Check connection")
      expect(page).to have_content("Account unavailable")
    end
    within("#account_#{cash.id}") do
      expect(page).to have_content("$0.00")
      expect(page).to have_content("Not connected")
    end
    row_selector = "#account_#{retirement.id}"
    trigger = find("#{row_selector} summary")
    trigger.send_keys(:enter)
    expect(page).to have_css("#{row_selector} details[open]")
    expect(page).to have_link("Edit balance")
    trigger.send_keys(:tab)
    expect(page.evaluate_script("document.activeElement.textContent.trim()")).to eq("Edit balance")
    page.driver.browser.action.send_keys(:escape).perform
    expect(page).not_to have_css("#{row_selector} details[open]")
    expect(page.evaluate_script("document.activeElement.getAttribute('aria-label')")).to eq("Actions for Retirement savings")
    trigger.click
    find("#tracked-accounts-title").click
    expect(page).not_to have_css("#{row_selector} details[open]")
    find("#tracked_accounts").native.save_screenshot(Rails.root.join("tmp/screenshots/tracked-accounts-design-desktop.png"))

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    page.refresh
    expect(page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")).to be <= 1
    within("#mobile_account_#{savings.account_id}") do
      expect(page).to have_link("Review balance")
      expect(page).to have_content("$4,850.00")
      find("summary").click
      expect(page).to have_link("Add balance")
      expect(page).to have_link("Manage connection")
      panel = find(".ta-row-actions-panel").native.rect
      expect(panel.x).to be >= 0
      expect(panel.x + panel.width).to be <= 390
      find("summary").click
    end
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 1800, deviceScaleFactor: 1, mobile: true)
    find("#tracked_accounts").native.save_screenshot(Rails.root.join("tmp/screenshots/tracked-accounts-design-mobile.png"))
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 320, height: 844, deviceScaleFactor: 1, mobile: true)
    expect(page.evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")).to be <= 1
    within("#mobile_account_#{savings.account_id}") do
      find("summary").click
      click_link "Add balance"
    end
    within("turbo-frame#mobile_snapshot_editor_account_#{savings.account_id}") do
      expect(page).to have_field("Balance")
      fill_in "Balance", with: "4600"
      click_button "Record Balance"
    end
    expect(page).to have_content("Balance snapshot recorded.")
    within("#mobile_account_#{savings.account_id}") do
      expect(page).to have_content("$4,600.00")
      expect(page).to have_content("$4,850.00")
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
