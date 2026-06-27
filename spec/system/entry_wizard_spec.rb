require "rails_helper"

RSpec.describe "Entry wizard", type: :system do
  it "renders the wizard modal and saves an entry from its form" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

    sign_in_as(user)

    visit new_wizard_budget_month_expense_entries_path(budget_month)

    expect(page).to have_content("Add Entry with Wizard")

    select "Income", from: "Section", visible: :all
    select "Planned", from: "Status", visible: :all
    select "Need", from: "Need / Want (optional)", visible: :all
    fill_in "Category", with: "Paycheck", visible: :all
    fill_in "Payee", with: "Consulting Client", visible: :all
    select "Checking", from: "Money leaves / activity account", visible: :all
    fill_in "Notes", with: "Wizard flow", visible: :all
    fill_in "Date", with: "2026-03-18", visible: :all
    fill_in "Planned amount", with: "1400", visible: :all
    click_button "Save Entry", visible: :all

    expect(page).to have_current_path(budget_month_tab_path(budget_month, "entries"), ignore_query: false)
    entry = budget_month.expense_entries.find_by!(payee: "Consulting Client")
    expect(entry.source_account).to eq(checking)
    expect(entry.account).to eq("Checking")
  end

  it "saves transfer-style account links from the wizard" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    card = create(:account, user: user, name: "Rewards Visa", kind: :credit_card)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

    sign_in_as(user)

    visit new_wizard_budget_month_expense_entries_path(budget_month)

    select "Debt or card payment", from: "Section", visible: :all
    select "Planned", from: "Status", visible: :all
    select "Need", from: "Need / Want (optional)", visible: :all
    fill_in "Category", with: "Credit card payment", visible: :all
    fill_in "Payee", with: "Rewards Visa", visible: :all
    select "Checking", from: "Money leaves / activity account", visible: :all
    select "Rewards Visa", from: "Money goes to", visible: :all
    fill_in "Date", with: "2026-03-18", visible: :all
    fill_in "Planned amount", with: "250", visible: :all
    click_button "Save Entry", visible: :all

    entry = budget_month.expense_entries.find_by!(payee: "Rewards Visa")
    expect(entry.source_account).to eq(checking)
    expect(entry.destination_account).to eq(card)
  end

  it "can save a subscription template alongside the wizard entry" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

    sign_in_as(user)

    visit new_wizard_budget_month_expense_entries_path(budget_month)

    select "Fixed bill", from: "Section", visible: :all
    select "Planned", from: "Status", visible: :all
    select "Need", from: "Need / Want (optional)", visible: :all
    fill_in "Category", with: "Streaming", visible: :all
    fill_in "Payee", with: "Netflix", visible: :all
    fill_in "Manual account label", with: "Checking", visible: :all
    fill_in "Notes", with: "Save as template", visible: :all
    fill_in "Date", with: "2026-03-08", visible: :all
    fill_in "Planned amount", with: "19.99", visible: :all
    check "Save as recurring", visible: :all
    select "Subscription", from: "What should repeat?", visible: :all
    fill_in "Day of month", with: "8", visible: :all
    click_button "Save Entry", visible: :all

    expect(page).to have_current_path(budget_month_tab_path(budget_month, "entries"), ignore_query: false)
    expect(budget_month.expense_entries.where(payee: "Netflix").exists?).to be(true)
    expect(user.subscriptions.order(:created_at).last.name).to eq("Netflix")
  end

  it "shows a pending save state while the turbo submission is in flight", js: true do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

    sign_in_as(user)
    visit budget_month_path(budget_month)

    click_link "Plan and Edit"
    expect(page).to have_content("Plan and Edit This Month")
    expect(page).to have_link("Open Guided Wizard")
    click_link "Open Guided Wizard"

    expect(page).to have_css("turbo-frame#entry_wizard_modal h3", text: "Add Entry with Wizard")
    expect(page).to have_css("turbo-frame#entry_wizard_modal select#expense_entry_section", visible: :all)
    modal_parent = page.evaluate_script('document.querySelector("turbo-frame#entry_wizard_modal").parentElement.tagName')
    modal_z_index = page.evaluate_script('Number(getComputedStyle(document.querySelector("turbo-frame#entry_wizard_modal").firstElementChild).zIndex)')
    topbar_z_index = page.evaluate_script('Number(getComputedStyle(document.querySelector(".ta-topbar")).zIndex)')

    expect(modal_parent).to eq("BODY")
    expect(modal_z_index).to be > topbar_z_index

    wizard_frame = find("turbo-frame#entry_wizard_modal", visible: false)
    expect(wizard_frame).to have_text("Add Entry with Wizard")
    expect(wizard_frame).to have_css("select#expense_entry_section", visible: :all)

    within(wizard_frame) do
      select "Income", from: "Section", visible: :all
      select "Planned", from: "Status", visible: :all
      click_button "Next"

      fill_in "Category", with: "Paycheck", visible: :all
      fill_in "Payee", with: "Consulting Client", visible: :all
      fill_in "Manual account label", with: "Checking", visible: :all
      click_button "Next"

      fill_in "Date", with: "2026-03-18", visible: :all
      fill_in "Planned amount", with: "1400", visible: :all
      click_button "Next"
    end

    execute_script(<<~JS)
      window.__originalWizardFetch = window.fetch.bind(window)
      window.fetch = (...args) => new Promise((resolve, reject) => {
        setTimeout(() => {
          window.__originalWizardFetch(...args).then(resolve).catch(reject)
        }, 400)
      })
    JS

    within(wizard_frame) do
      click_button "Save Entry"
    end

    expect(page).to have_css("turbo-frame#entry_wizard_modal button[aria-busy='true'][disabled]", text: "Saving entry...")
    expect(page).to have_no_css("turbo-frame#entry_wizard_modal [data-entry-wizard-target='submitSpinner']", visible: :all)
    expect(page).to have_css("turbo-frame#entry_wizard_modal button[data-entry-wizard-target='cancelButton'][disabled]", text: "Cancel")

    expect(page).to have_content("Entry added.")
  end

  it "keeps the submit button disabled until review-step requirements are complete", js: true do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

    sign_in_as(user)
    visit budget_month_path(budget_month)

    click_link "Plan and Edit"
    expect(page).to have_content("Plan and Edit This Month")
    expect(page).to have_link("Open Guided Wizard")
    click_link "Open Guided Wizard"

    expect(page).to have_css("turbo-frame#entry_wizard_modal h3", text: "Add Entry with Wizard")
    expect(page).to have_css("turbo-frame#entry_wizard_modal select#expense_entry_section", visible: :all)
    wizard_frame = find("turbo-frame#entry_wizard_modal", visible: false)

    within(wizard_frame) do
      click_button "Fixed bill"
      expect(page).to have_css("button[data-section-value='fixed'][aria-pressed='true']", text: "Fixed bill")
      select "Planned", from: "Status", visible: :all
      click_button "Next"

      expect(page).to have_content("Account flow examples")
      expect(page).to have_content("Money leaves checking. Money goes to the card being paid down.")

      fill_in "Category", with: "Streaming", visible: :all
      fill_in "Payee", with: "Movie Box", visible: :all
      fill_in "Manual account label", with: "Checking", visible: :all
      click_button "Next"

      fill_in "Date", with: "2026-03-18", visible: :all
      fill_in "Planned amount", with: "19.99", visible: :all
      click_button "Next"

      expect(page).to have_css("button[data-entry-wizard-target='submitButton']:not([disabled])", text: "Save Entry")

      check "Save as recurring", visible: :all
      expect(page).to have_css("button[data-entry-wizard-target='submitButton'][disabled]", text: "Save Entry")

      select "Subscription", from: "What should repeat?", visible: :all
      expect(page).to have_css("button[data-entry-wizard-target='submitButton'][disabled]", text: "Save Entry")

      fill_in "Day of month", with: "18", visible: :all
      expect(page).to have_css("button[data-entry-wizard-target='submitButton']:not([disabled])", text: "Save Entry")
    end
  end

  it "recovers cleanly when a turbo wizard submission returns validation errors", js: true do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    other_user = create(:user)
    other_subscription = create(:subscription, user: other_user, name: "Other User Subscription")
    forged_token = "#{other_subscription.class.name}:#{other_subscription.id}"

    sign_in_as(user)
    visit budget_month_path(budget_month)

    click_link "Plan and Edit"
    expect(page).to have_content("Plan and Edit This Month")
    expect(page).to have_link("Open Guided Wizard")
    click_link "Open Guided Wizard"

    expect(page).to have_css("turbo-frame#entry_wizard_modal h3", text: "Add Entry with Wizard")
    expect(page).to have_css("turbo-frame#entry_wizard_modal select#expense_entry_section", visible: :all)
    wizard_frame = find("turbo-frame#entry_wizard_modal", visible: false)
    expect(wizard_frame).to have_text("Add Entry with Wizard")
    expect(wizard_frame).to have_css("select#expense_entry_section", visible: :all)

    within(wizard_frame) do
      select "Fixed bill", from: "Section", visible: :all
      select "Planned", from: "Status", visible: :all
      click_button "Next"

      fill_in "Category", with: "Streaming", visible: :all
      fill_in "Payee", with: "Movie Box", visible: :all
      fill_in "Manual account label", with: "Checking", visible: :all
      click_button "Next"

      fill_in "Date", with: "2026-03-18", visible: :all
      fill_in "Planned amount", with: "19.99", visible: :all
      click_button "Next"
    end

    execute_script(<<~JS)
      const select = document.querySelector("turbo-frame#entry_wizard_modal select#recurring_link")
      const option = document.createElement("option")
      option.value = "#{forged_token}"
      option.textContent = "Forged recurring link"
      select.appendChild(option)
      select.value = "#{forged_token}"
      select.dispatchEvent(new Event("change", { bubbles: true }))

      window.__originalWizardFetch = window.fetch.bind(window)
      window.fetch = (...args) => new Promise((resolve, reject) => {
        setTimeout(() => {
          window.__originalWizardFetch(...args).then(resolve).catch(reject)
        }, 400)
      })
    JS

    within(wizard_frame) do
      click_button "Save Entry"
    end

    expect(page).to have_css("turbo-frame#entry_wizard_modal button[aria-busy='true'][disabled]", text: "Saving entry...")
    expect(page).to have_no_css("turbo-frame#entry_wizard_modal [data-entry-wizard-target='submitSpinner']", visible: :all)
    expect(page).to have_css("turbo-frame#entry_wizard_modal button[data-entry-wizard-target='cancelButton'][disabled]", text: "Cancel")

    expect(page).to have_css("turbo-frame#entry_wizard_modal", visible: false)
    expect(page).to have_content("Choose a valid recurring transaction to link.")
    expect(page).to have_no_css("turbo-frame#entry_wizard_modal button[aria-busy='true']")
    expect(page).to have_css("turbo-frame#entry_wizard_modal button[data-entry-wizard-target='cancelButton']:not([disabled])", text: "Cancel")
    expect(page).to have_css("turbo-frame#entry_wizard_modal button[data-entry-wizard-target='nextButton']:not([disabled])", text: "Next")
    expect(budget_month.expense_entries.reload.count).to eq(0)
  end
end
