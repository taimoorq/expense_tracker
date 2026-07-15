require "rails_helper"

RSpec.describe "Budget month authorization", type: :request do
  it "does not allow a signed in user to access another user's month" do
    signed_in_user = create(:user)
    other_month = create(:budget_month, label: "Private Month")

    sign_in signed_in_user
    get budget_month_path(other_month)

    expect(response).to have_http_status(:not_found)
  end

  it "renders only the entries matching a valid review reason" do
    user = create(:user)
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month)
    create(:expense_entry, user: user, budget_month: month, occurred_on: Date.current, status: :planned, payee: "Due utility", category: "Utilities")
    create(:expense_entry, user: user, budget_month: month, occurred_on: Date.current + 5.days, status: :planned, payee: "Future utility", category: "Utilities")

    sign_in user
    get budget_month_tab_path(month, "entries", review: "due")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Review mode")
    expect(response.body).to include("Due utility")
    expect(response.body).not_to include("Future utility")
    expect(response.body).to include('aria-current="true"')
  end

  it "ignores unsupported review reasons without exposing review results" do
    user = create(:user)
    month = create(:budget_month, user: user)
    create(:expense_entry, user: user, budget_month: month, occurred_on: Date.current, status: :planned, payee: "Private item")

    sign_in user
    get budget_month_tab_path(month, "entries", review: "not-a-review")

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Review mode")
    expect(response.body).not_to include("Private item")
  end
end
