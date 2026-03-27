require "rails_helper"

RSpec.describe "User menu", type: :system, js: true do
  it "shows profile and sign out options from a single topbar icon" do
    user = create(:user)

    sign_in_as(user)
    visit root_path

    find("button[aria-label='Open account menu']").click

    expect(page).to have_content(user.email)
    expect(page).to have_link("Profile settings", href: edit_user_registration_path)
    expect(page).to have_button("Sign out")
  end
end
