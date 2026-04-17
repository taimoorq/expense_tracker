require "rails_helper"

RSpec.describe "User menu", type: :system, js: true do
  it "shows the profile menu beneath settings in the sidebar" do
    user = create(:user)

    sign_in_as(user)
    visit root_path

    expect(page).to have_link("Settings", href: settings_path)
    find("button[aria-label='Open profile menu']").click

    expect(page).to have_content(user.email)
    expect(page).to have_link("Profile", href: profile_path)
    expect(page).to have_button("Sign out")
  end
end
