require "rails_helper"

RSpec.describe "Entry wizard", type: :system do
  it "renders the wizard modal and saves an entry from its form" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

    sign_in_as(user)

    visit new_wizard_budget_month_expense_entries_path(budget_month)

    expect(page).to have_content("Add Entry with Wizard")

    select "Income", from: "Section", visible: :all
    select "Planned", from: "Status", visible: :all
    select "Need", from: "Need / Want", visible: :all
    fill_in "Category", with: "Paycheck", visible: :all
    fill_in "Payee", with: "Consulting Client", visible: :all
    fill_in "Account", with: "Checking", visible: :all
    fill_in "Notes", with: "Wizard flow", visible: :all
    fill_in "Date", with: "2026-03-18", visible: :all
    fill_in "Planned amount", with: "1400", visible: :all
    click_button "Save Entry", visible: :all

    expect(page).to have_current_path(budget_month_tab_path(budget_month, "entries"), ignore_query: false)
    expect(budget_month.expense_entries.where(payee: "Consulting Client").exists?).to be(true)
  end

  it "can save a subscription template alongside the wizard entry" do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

    sign_in_as(user)

    visit new_wizard_budget_month_expense_entries_path(budget_month)

    select "Fixed", from: "Section", visible: :all
    select "Planned", from: "Status", visible: :all
    select "Need", from: "Need / Want", visible: :all
    fill_in "Category", with: "Streaming", visible: :all
    fill_in "Payee", with: "Netflix", visible: :all
    fill_in "Account", with: "Checking", visible: :all
    fill_in "Notes", with: "Save as template", visible: :all
    fill_in "Date", with: "2026-03-08", visible: :all
    fill_in "Planned amount", with: "19.99", visible: :all
    check "Save as recurring", visible: :all
    select "Subscription", from: "Recurring Transaction Type", visible: :all
    fill_in "Due Day", with: "8", visible: :all
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
      fill_in "Account", with: "Checking", visible: :all
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
    expect(page).to have_css("turbo-frame#entry_wizard_modal button[data-entry-wizard-target='cancelButton'][disabled]", text: "Cancel")

    expect(page).to have_content("Entry added.")
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
      select "Fixed", from: "Section", visible: :all
      select "Planned", from: "Status", visible: :all
      click_button "Next"

      fill_in "Category", with: "Streaming", visible: :all
      fill_in "Payee", with: "Movie Box", visible: :all
      fill_in "Account", with: "Checking", visible: :all
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
    expect(page).to have_css("turbo-frame#entry_wizard_modal button[data-entry-wizard-target='cancelButton'][disabled]", text: "Cancel")

    expect(page).to have_css("turbo-frame#entry_wizard_modal", visible: false)
    expect(page).to have_content("Choose a valid recurring transaction to link.")
    expect(page).to have_no_css("turbo-frame#entry_wizard_modal button[aria-busy='true']")
    expect(page).to have_css("turbo-frame#entry_wizard_modal button[data-entry-wizard-target='cancelButton']:not([disabled])", text: "Cancel")
    expect(page).to have_css("turbo-frame#entry_wizard_modal button[data-entry-wizard-target='nextButton']:not([disabled])", text: "Next")
    expect(budget_month.expense_entries.reload.count).to eq(0)
  end
end
