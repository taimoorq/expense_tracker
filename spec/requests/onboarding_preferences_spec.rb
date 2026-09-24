require "rails_helper"

RSpec.describe "Onboarding preferences", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "persists versioned setup progress and lets the user hide and restore the checklist" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("0 of 4 foundations complete", "Hide for now")
    membership = user.reload.workspace_memberships.sole
    expect(membership.onboarding_version).to eq(Overview::OnboardingProgress::VERSION)

    patch onboarding_preference_path, params: { dismissed: true }

    expect(response).to redirect_to(root_path)
    expect(membership.reload.onboarding_dismissed_at).to be_present

    get root_path
    expect(response.body).not_to include("Choose how you want to start")

    patch onboarding_preference_path, params: { dismissed: false }
    expect(membership.reload.onboarding_dismissed_at).to be_nil
  end

  it "persists completion when every derived foundation is complete" do
    account = create(:account, user: user)
    create(:account_snapshot, account: account, recorded_on: Date.current, balance: 1_000)
    create(:pay_schedule, user: user, linked_account: account, amount: 2_000, first_pay_on: Date.current.beginning_of_month)
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month)
    create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      section: :income,
      status: :paid,
      planned_amount: 2_000,
      actual_amount: 2_000,
      occurred_on: Date.current
    )

    get root_path

    membership = user.reload.workspace_memberships.sole
    expect(membership.onboarding_completed_at).to be_present
    expect(response.body).not_to include("Choose how you want to start")
  end

  it "offers both paths and does not reset an existing dismissal on version changes" do
    membership = Identity::PersonalWorkspaceProvisioner.call(user: user).membership
    membership.update!(onboarding_version: "financial-foundations-v1", onboarding_dismissed_at: 1.day.ago)
    get root_path
    expect(membership.reload.onboarding_dismissed_at).to be_present
    expect(response.body).not_to include("Choose how you want to start")

    patch onboarding_preference_path, params: { dismissed: false }
    get root_path
    expect(response.body).to include("Connect with SimpleFIN", "Track without a connection")
  end

  it "remembers optional steps and supports setup without recurring templates" do
    account = create(:account, user: user)
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month)
    create(:expense_entry, user: user, budget_month: month, source_account: account)
    patch onboarding_preference_path, params: { path: "manual", skip: "recurring" }
    patch onboarding_preference_path, params: { skip: "balance" }
    patch onboarding_preference_path, params: { reviewed: "1" }
    get root_path

    membership = user.reload.workspace_memberships.sole
    expect(membership.onboarding_path).to eq("manual")
    expect(membership.onboarding_completed_at).to be_present
    expect(response.body).not_to include("Choose how you want to start")
  end

  it "routes statement setup through explicit account selection" do
    patch onboarding_preference_path, params: { path: "import", start: "1" }
    expect(response).to redirect_to(activity_import_path)
    get activity_import_path
    expect(response.body).to include("Add an account")
  end

  it "lets manual users change timezone in Workspace settings" do
    patch workspace_settings_path, params: { workspace: { time_zone: "America/New_York" } }
    expect(response).to redirect_to(settings_path(anchor: "workspace"))
    expect(user.reload.legacy_owned_budget_workspace.time_zone).to eq("America/New_York")
    patch workspace_settings_path, params: { workspace: { time_zone: "Invalid/Zone" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Workspace timezone", "is not included")
  end
end
