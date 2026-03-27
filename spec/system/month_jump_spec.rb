require "rails_helper"

RSpec.describe "Month jump", type: :system, js: true do
  it "lets a user jump to a saved month from the top navbar autocomplete" do
    user = create(:user)
    create(:budget_month, user: user, month_on: Date.new(2026, 1, 1), label: "January 2026")
    target_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")

    sign_in_as(user)
    visit root_path

    fill_in "Jump to month", with: "mar"

    expect(page).to have_css("[data-month-jump-target='panel']:not(.hidden)")
    expect(page).to have_button("March 2026")

    click_button "March 2026"

    expect(page).to have_current_path(budget_month_path(target_month))
    expect(page).to have_content("March 2026")
  end
end
