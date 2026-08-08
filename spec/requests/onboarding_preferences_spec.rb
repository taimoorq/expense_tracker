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
end
