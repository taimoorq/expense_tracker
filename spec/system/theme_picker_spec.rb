require "rails_helper"

RSpec.describe "Theme picker", type: :system, js: true do
  it "updates the app theme when a new color scheme is selected" do
    user = create(:user)

    sign_in_as(user)
    visit settings_path

    select "Indigo", from: "Color scheme"

    expect(page).to have_css("body.ta-theme-indigo", wait: 5)
    expect(page).to have_css("meta[name='theme-color'][content='#4F46E5']", visible: false, wait: 5)
    expect(page).to have_css(".ta-theme-swatches[aria-label='Indigo palette']", wait: 5)
  end
end
