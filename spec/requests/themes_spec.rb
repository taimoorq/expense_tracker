require "rails_helper"

RSpec.describe "Themes", type: :request do
  let(:user) { create(:user) }

  before do
    post user_session_path, params: {
      user: {
        email: user.email,
        password: user.password
      }
    }
  end

  it "updates the theme cookie and applies the selected theme on the next page" do
    patch theme_path, params: { theme: "indigo" }, headers: { "HTTP_REFERER" => settings_path }

    expect(response).to redirect_to(settings_path)

    follow_redirect!

    expect(response.body).to include("ta-theme-indigo")
    expect(response.body).to include("aria-label=\"Indigo palette\"")
    expect(response.body).to include("background-color: #4F46E5")
    expect(response.body).to match(/<option[^>]*(selected=\"selected\"[^>]*value=\"indigo\"|value=\"indigo\"[^>]*selected=\"selected\")/)
  end

  it "falls back to the default theme when an unknown key is posted" do
    patch theme_path, params: { theme: "unknown" }, headers: { "HTTP_REFERER" => settings_path }

    follow_redirect!

    expect(response.body).to include("ta-theme-earth")
    expect(response.body).to include("aria-label=\"Earth palette\"")
    expect(response.body).to match(/<option[^>]*(selected=\"selected\"[^>]*value=\"earth\"|value=\"earth\"[^>]*selected=\"selected\")/)
  end

  it "shows the settings page with the theme picker" do
    get settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Appearance and app settings")
    expect(response.body).to include("Choose your palette")
    expect(response.body).to include("aria-label=\"Earth palette\"")
  end
end
