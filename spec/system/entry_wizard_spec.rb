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

    expect(page).to have_content("Entry added.")
    expect(page).to have_content("Consulting Client")
  end
end