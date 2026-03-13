require "rails_helper"

RSpec.describe "User data privacy", type: :system do
  it "shows only the signed in user's budget months" do
    current_user = create(:user, email: "owner@example.com")
    other_user = create(:user, email: "other@example.com")

    create(:budget_month, user: current_user, month_on: Date.new(2026, 3, 1), label: "March 2026")
    create(:budget_month, user: other_user, month_on: Date.new(2026, 4, 1), label: "April 2026")

    visit new_user_session_path

    fill_in "Email", with: current_user.email
    fill_in "Password", with: "password123!"
    click_button "Log in"

    expect(page).to have_content("Signed in successfully")
    expect(page).to have_content("March 2026")
    expect(page).not_to have_content("April 2026")
  end
end
