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

  it "links GitHub update notices to the README update instructions" do
    allow(Platform::GitHubUpdateChecker).to receive(:available_update).and_return(
      Platform::GitHubUpdateChecker::Release.new(
        version: "999.0.0",
        tag_name: "v999.0.0",
        name: "Future release",
        html_url: "https://github.com/taimoorq/expense_tracker/releases/tag/v999.0.0"
      )
    )
    allow(Platform::GitHubUpdateChecker).to receive(:readme_update_url)
      .and_return("https://github.com/taimoorq/expense_tracker#updating-a-self-hosted-install")

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Update Available")
    expect(response.body).to include("https://github.com/taimoorq/expense_tracker#updating-a-self-hosted-install")
  end
end
