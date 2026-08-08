require "rails_helper"

RSpec.describe "Overview", type: :request do
  it "renders target-backed graphs with calculation labels, exact values, and Activity drilldowns" do
    user = create(:user)
    checking = create(:account, user: user, name: "Checking", kind: :checking)
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))
    create(:expense_entry, user: user, budget_month: month, source_account: checking, section: :income, payee: "Employer", planned_amount: 2_000, actual_amount: 2_100, status: :paid)
    create(:expense_entry, user: user, budget_month: month, source_account: checking, section: :fixed, category: "Housing", payee: "Rent", planned_amount: 800, actual_amount: 825, status: :paid)
    backfill = Platform::TargetBackfill::Runner.call(user: user)
    backfill.workspace.update!(target_writes_enabled: true, target_reads_enabled: true)
    sign_in user

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Calculation target-v1", "Review exact flow values", "Review exact account totals", "Review exact bank movement")
    expect(response.body).to include("$2,100.00", "$825.00", "Review posted bank transactions in Activity")
    expect(response.body).to include(activity_path(view: "all"))
  end
end
