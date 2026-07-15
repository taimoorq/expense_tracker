require "rails_helper"

RSpec.describe "Profile", type: :request do
  let(:user) do
    create(
      :user,
      email: "profile@example.com",
      default_landing_page: "accounts",
      preferred_month_view: "calendar"
    )
  end

  before do
    post user_session_path, params: {
      user: {
        email: user.email,
        password: user.password
      }
    }
  end

  it "shows identity details and links to the dedicated edit surfaces" do
    get profile_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<h1 class=\"ta-page-title inline-flex items-center gap-2\">")
    expect(response.body).to include("<span class=\"min-w-0\">Profile</span>")
    expect(response.body).to include(user.email)
    expect(response.body).to include("Sign-in details")
    expect(response.body).not_to include("Default landing page")
    expect(response.body).not_to include("Preferred month view")
    expect(response.body).to include(edit_user_registration_path)
    expect(response.body).to include(settings_path)
  end
end
