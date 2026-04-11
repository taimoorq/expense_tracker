require "rails_helper"

RSpec.describe "Entry editor", type: :system do
  it "recovers cleanly when a turbo editor submission returns validation errors", js: true do
    user = create(:user)
    budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    entry = create(:expense_entry,
      budget_month: budget_month,
      user: user,
      occurred_on: Date.new(2026, 3, 8),
      section: :fixed,
      category: "Utilities",
      payee: "Water",
      planned_amount: 88.45,
      status: :planned)
    other_user = create(:user)
    other_account = create(:account, user: other_user, name: "Other Checking")

    sign_in_as(user)
    visit budget_month_path(budget_month)

    find('a[aria-label="Edit entry"]', match: :first).click

    expect(page).to have_css("turbo-frame#entry_editor_modal")

    within("turbo-frame#entry_editor_modal") do
      fill_in "Payee", with: "Updated Water"
    end

    execute_script(<<~JS)
      const select = document.querySelector("turbo-frame#entry_editor_modal select[name='expense_entry[source_account_id]']")
      const option = document.createElement("option")
      option.value = "#{other_account.id}"
      option.textContent = "Forged account"
      select.appendChild(option)
      select.value = "#{other_account.id}"
      select.dispatchEvent(new Event("change", { bubbles: true }))

      window.__originalEditorFetch = window.fetch.bind(window)
      window.fetch = (...args) => new Promise((resolve, reject) => {
        setTimeout(() => {
          window.__originalEditorFetch(...args).then(resolve).catch(reject)
        }, 400)
      })
    JS

    within("turbo-frame#entry_editor_modal") do
      click_button "Update Entry"
    end

    expect(page).to have_css("turbo-frame#entry_editor_modal button[aria-busy='true'][disabled]", text: "Saving changes...")
    expect(page).to have_css("turbo-frame#entry_editor_modal button[data-turbo-submit-target='cancelButton'][disabled]", text: "Cancel")

    expect(page).to have_css("turbo-frame#entry_editor_modal")
    expect(page).to have_content("Source account must belong to the same user")
    expect(page).to have_no_css("turbo-frame#entry_editor_modal button[aria-busy='true']")
    expect(page).to have_css("turbo-frame#entry_editor_modal button[data-turbo-submit-target='cancelButton']:not([disabled])", text: "Cancel")
    expect(page).to have_css("turbo-frame#entry_editor_modal button[data-turbo-submit-target='submitButton']:not([disabled])", text: "Update Entry")
    expect(entry.reload.payee).to eq("Water")
  end
end
