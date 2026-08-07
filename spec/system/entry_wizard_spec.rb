require "rails_helper"

RSpec.describe "Add entry composer", type: :system do
  it "saves a routine income entry from the direct full-page form" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    sign_in_as(user)

    visit new_wizard_budget_month_expense_entries_path(budget_month)

    expect(page).to have_css("h1", text: "Add entry")
    expect(page).to have_content("One-time entry")
    expect(page).to have_no_content("Step 1 of")

    select "Income", from: "Entry kind"
    select "Planned", from: "Status"
    fill_in "Payee", with: "Consulting Client"
    fill_in "Category", with: "Paycheck"
    fill_in "Date", with: "2026-03-18"
    fill_in "Amount", with: "1400"
    select "Checking", from: "Paid from or charged to"
    click_button "Add to March 2026"

    expect(page).to have_current_path(budget_month_tab_path(budget_month, "entries"), ignore_query: false)
    entry = budget_month.expense_entries.find_by!(payee: "Consulting Client")
    expect(entry.source_account).to eq(checking)
    expect(entry.account).to eq("Checking")
  end

  it "saves a two-sided card payment from the same one-screen form" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    card = create(:account, user: user, name: "Rewards Visa", kind: :credit_card)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    sign_in_as(user)

    visit new_wizard_budget_month_expense_entries_path(budget_month)

    select "Debt or card payment", from: "Entry kind"
    select "Planned", from: "Status"
    fill_in "Payee", with: "Rewards Visa"
    fill_in "Category", with: "Credit card payment"
    fill_in "Date", with: "2026-03-18"
    fill_in "Amount", with: "250"
    select "Checking", from: "Paid from or charged to"
    select "Rewards Visa", from: "Money goes to"
    click_button "Add to March 2026"

    entry = budget_month.expense_entries.find_by!(payee: "Rewards Visa")
    expect(entry.source_account).to eq(checking)
    expect(entry.destination_account).to eq(card)
  end

  it "saves and links a recurring subscription without a separate review step" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    sign_in_as(user)

    visit new_wizard_budget_month_expense_entries_path(budget_month)

    select "Fixed bill", from: "Entry kind"
    fill_in "Payee", with: "Netflix"
    fill_in "Category", with: "Streaming"
    fill_in "Date", with: "2026-03-08"
    fill_in "Amount", with: "19.99"
    check "planning_template_enabled", visible: :all
    select "Subscription", from: "What should repeat?", visible: :all
    fill_in "Day of month", with: "8", visible: :all
    click_button "Add to March 2026"

    entry = budget_month.expense_entries.find_by!(payee: "Netflix")
    subscription = user.subscriptions.find_by!(name: "Netflix")
    expect(entry.source_template).to eq(subscription)
    expect(entry).not_to be_generated_from_template
  end

  it "opens as a one-screen Turbo dialog and shows a pending state", js: true do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    sign_in_as(user)
    visit budget_month_tab_path(budget_month, "entries")

    within("turbo-frame#entry_form") { click_link "Add entry" }

    expect(page).to have_css("turbo-frame#entry_wizard_modal h2", text: "Add entry")
    expect(page).to have_no_button("Next")
    modal_parent = page.evaluate_script('document.querySelector("turbo-frame#entry_wizard_modal").parentElement.tagName')
    expect(modal_parent).to eq("BODY")

    within("turbo-frame#entry_wizard_modal") do
      select "Income", from: "Entry kind"
      fill_in "Paid by", with: "Consulting Client"
      fill_in "Category", with: "Paycheck"
      fill_in "Date", with: "03/18/2026"
      fill_in "Amount", with: "1400"
    end

    execute_script(<<~JS)
      document.addEventListener("turbo:before-fetch-request", (event) => {
        event.preventDefault()
        setTimeout(() => event.detail.resume(), 500)
      }, { once: true })
    JS

    within("turbo-frame#entry_wizard_modal") { click_button "Add to March 2026" }

    expect(page).to have_css("turbo-frame#entry_wizard_modal button[aria-busy='true'][disabled]", text: "Adding entry…")
    expect(page).to have_content("Entry added.")
  end

  it "prefills an existing recurring item and requires acknowledgement when it is already covered", js: true do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    card = create(:account, user: user, name: "Rewards Visa", kind: :credit_card)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    subscription = create(:subscription, user: user, name: "Netflix", amount: 19.99, due_day: 8, linked_account: checking)
    create(
      :expense_entry,
      budget_month: budget_month,
      occurred_on: Date.new(2026, 3, 8),
      section: :fixed,
      category: "Subscription",
      payee: "Netflix",
      planned_amount: 19.99,
      account: "Checking",
      source_account: checking,
      source_template: subscription,
      source_file: "subscription"
    )
    sign_in_as(user)
    visit budget_month_tab_path(budget_month, "entries")

    within("turbo-frame#entry_form") { click_link "Add entry" }
    within("turbo-frame#entry_wizard_modal") do
      select "Debt or card payment", from: "Entry kind"
      select "Checking", from: "Paid from"
      select card.name, from: "Money goes to"
      find("label", text: "Existing recurring").click
      select "Netflix — Already added for March 2026", from: "Recurring item"

      expect(page).to have_field("Payee", with: "Netflix")
      expect(page).to have_field("Amount", with: "19.99")
      expect(page).to have_select("Paid from or charged to", selected: "Checking")
      expect(page).to have_select("Money goes to", selected: "No destination account", visible: :all)
      expect(page).to have_content("Confirm this unusual occurrence.")

      click_button "Add to March 2026"
      expect(page).to have_content("Confirm that this is an extra occurrence")

      check "Confirm this unusual occurrence. Add another or off-schedule occurrence anyway."
      click_button "Add to March 2026"
    end

    expect(page).to have_content("Entry added.")
    expect(budget_month.expense_entries.where(source_template: subscription).count).to eq(2)
  end

  it "recovers in place from a server validation error with values preserved", js: true do
    user = create(:user)
    other_user = create(:user)
    other_subscription = create(:subscription, user: other_user, name: "Private subscription")
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    forged_token = "Subscription:#{other_subscription.id}"
    sign_in_as(user)
    visit budget_month_tab_path(budget_month, "entries")

    within("turbo-frame#entry_form") { click_link "Add entry" }
    within("turbo-frame#entry_wizard_modal") do
      find("label", text: "Existing recurring").click
      execute_script(<<~JS)
        const select = document.querySelector("turbo-frame#entry_wizard_modal select#recurring_link")
        const option = document.createElement("option")
        option.value = "#{forged_token}"
        option.textContent = "Forged recurring item"
        option.dataset.prefill = "{}"
        option.dataset.extraRequired = "false"
        select.appendChild(option)
        select.value = "#{forged_token}"
        select.dispatchEvent(new Event("change", { bubbles: true }))
      JS
      fill_in "Payee", with: "Movie Box"
      fill_in "Category", with: "Streaming"
      fill_in "Date", with: "03/18/2026"
      fill_in "Amount", with: "19.99"
      click_button "Add to March 2026"
    end

    expect(page).to have_css("turbo-frame#entry_wizard_modal")
    expect(page).to have_content("Choose a valid recurring transaction to link.")
    expect(page).to have_field("Payee", with: "Movie Box", visible: :all)
    expect(page).to have_button("Add to March 2026", disabled: false)
    expect(budget_month.expense_entries.reload.count).to eq(0)
  end
end
