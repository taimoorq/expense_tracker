require "rails_helper"

RSpec.describe "Budget month management", type: :system do
  it "allows a signed in user to create a budget month" do
    user = create(:user, email: "planner@example.com")

    sign_in_as(user)
    visit new_budget_month_path

    fill_in "Month", with: "2026-05-01"
    fill_in "Label", with: "May 2026"
    fill_in "Planned income", with: "7200"
    click_button "Create"

    expect(page).to have_content("Budget month created.")
    expect(page).to have_content("May 2026")
  end

  it "allows a signed in user to sign out" do
    user = create(:user, email: "signout@example.com")

    sign_in_as(user)
    click_button "Sign out"

    expect(page).to have_content("Signed out successfully")
    expect(page).to have_content("Create account")
  end
end