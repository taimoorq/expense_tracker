require "rails_helper"

RSpec.describe "Help and release notes", type: :request do
  let(:user) { create(:user) }

  before do
    post user_session_path, params: {
      user: {
        email: user.email,
        password: user.password
      }
    }
  end

  it "shows the unread release banner and release history" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("New update available")
    expect(response.body).to include("v0.4.0")

    get help_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("What's new")
    expect(response.body).to include("In-app release notes")
    expect(response.body).to include("New to you")
  end

  it "marks a release as read for the current user" do
    patch acknowledge_help_release_notes_path, params: { version: "0.4.0" }

    expect(response).to redirect_to(help_path(anchor: "whats-new"))

    user.reload

    expect(user.last_seen_release_version).to eq("0.4.0")

    get root_path

    expect(response.body).not_to include("New update available")
  end
end
