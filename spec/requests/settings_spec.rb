require "rails_helper"

RSpec.describe "Settings", type: :request do
  let(:user) { create(:user) }

  before do
    post user_session_path, params: {
      user: {
        email: user.email,
        password: user.password
      }
    }
  end

  it "updates workflow preferences" do
    patch settings_path, params: {
      user: {
        default_landing_page: "months",
        preferred_month_view: "calendar"
      }
    }

    expect(response).to redirect_to(settings_path)

    user.reload

    expect(user.default_landing_page).to eq("months")
    expect(user.preferred_month_view).to eq("calendar")
  end

  it "uses the preferred month view when no tab is requested" do
    user.update!(preferred_month_view: "calendar")
    budget_month = create(:budget_month, user: user)
    create(:expense_entry, budget_month: budget_month, user: user)

    get budget_month_path(budget_month)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(href="#{budget_month_tab_path(budget_month, "calendar")}"))
    expect(response.body).to include('aria-selected="true"')
  end

  it "places the quick actions section above the continue section on overview" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Quick Actions")
    expect(response.body.index("Quick Actions")).to be < response.body.index("Continue")
    expect(response.body).to include("<details class=\"ta-card group\">")
  end

  it "uses the saved landing page after a fresh sign in" do
    user.update!(default_landing_page: "months")
    delete destroy_user_session_path

    post user_session_path, params: {
      user: {
        email: user.email,
        password: user.password
      }
    }

    expect(response).to redirect_to(budget_months_path)
  end
end
