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

  it "shows the current user profile details and settings summary" do
    get profile_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Your profile")
    expect(response.body).to include(user.email)
    expect(response.body).to include("Accounts &amp; Net Worth")
    expect(response.body).to include("Calendar")
    expect(response.body).to include(edit_user_registration_path)
    expect(response.body).to include(settings_path)
  end
end
