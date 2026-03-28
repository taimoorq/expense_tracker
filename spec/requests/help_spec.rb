require "rails_helper"

RSpec.describe "Help and release notes", type: :request do
  let(:user) { create(:user) }
  let(:latest_release) { ReleaseCatalog.latest }

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
    expect(response.body).to include(latest_release.title)

    get help_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Release notes")
    expect(response.body).to include("Open release notes")

    get help_releases_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("What's new")
    expect(response.body).to include(latest_release.title)
    expect(response.body).to include("New to you")
  end

  it "marks a release as read for the current user" do
    patch acknowledge_help_release_notes_path, params: { version: latest_release.version }

    expect(response).to redirect_to(help_releases_path)

    user.reload

    expect(user.last_seen_release_version).to eq(latest_release.version)

    delete destroy_user_session_path
    post user_session_path, params: {
      user: {
        email: user.email,
        password: user.password
      }
    }

    get root_path

    expect(response.body).not_to include("New update available")
  end
end
