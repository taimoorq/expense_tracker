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
    check "Save as template", visible: :all
    select "Subscription", from: "Template Type", visible: :all
    fill_in "Due Day", with: "8", visible: :all
    click_button "Save Entry", visible: :all

    expect(page).to have_content("Entry and planning template added.")
    expect(page).to have_content("Netflix")
    expect(user.subscriptions.order(:created_at).last.name).to eq("Netflix")
  end
end
