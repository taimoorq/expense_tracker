require "rails_helper"

RSpec.describe "Budget month authorization", type: :request do
  it "does not allow a signed in user to access another user's month" do
    signed_in_user = create(:user)
    other_month = create(:budget_month, label: "Private Month")

    sign_in signed_in_user
    get budget_month_path(other_month)

    expect(response).to have_http_status(:not_found)
  end
end
