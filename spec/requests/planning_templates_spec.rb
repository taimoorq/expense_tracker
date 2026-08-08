require "rails_helper"

RSpec.describe "Planning templates", type: :request do
  it "shows the target 90-day commitments visual and exact table after read cutover" do
    user = create(:user)
    create(:monthly_bill, user: user, name: "Power bill", default_amount: 125, due_day: Date.current.day)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.update!(target_writes_enabled: true, target_reads_enabled: true)
    sign_in user

    get planning_templates_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      "Upcoming 90-day commitments",
      "Power bill",
      "Planned commitments",
      "target-v1",
      "$125.00"
    )
  end
end
