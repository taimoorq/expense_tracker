require "rails_helper"

RSpec.describe "Sidebar navigation", type: :system, js: true do
  it "opens settings as a full-page visit from a month detail page" do
    user = create(:user, email: "sidebar-settings@example.com")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    create(:expense_entry, budget_month: month, user: user, payee: "Rent", planned_amount: 1200)

    sign_in_as(user)
    visit budget_month_path(month)

    click_link "Settings"

    expect(page).to have_current_path(settings_path)
    expect(page).to have_content("Appearance and app settings")
  end
end
