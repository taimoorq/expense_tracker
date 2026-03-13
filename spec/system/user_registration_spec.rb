require "rails_helper"

RSpec.describe "User registration", type: :system do
  it "allows a new user to create an account" do
    visit new_user_registration_path

    fill_in "Email", with: "newuser@example.com"
    fill_in "Password", with: "password123!"
    fill_in "Password confirmation", with: "password123!"
    click_button "Sign up"

    expect(page).to have_content("Welcome! You have signed up successfully")
    expect(page).to have_content("newuser@example.com")
    expect(page).to have_content("Budget Months")
  end
end
