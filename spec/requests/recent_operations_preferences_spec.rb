require "rails_helper"

RSpec.describe "Recent operation preferences", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  before { sign_in user }

  it "dismisses completed status until a newer operation is saved" do
    provisioned = Identity::PersonalWorkspaceProvisioner.call(user: user)
    create(
      :operation_run,
      budget_workspace: provisioned.workspace,
      actor_membership: provisioned.membership,
      operation_type: "backup_v2_export",
      state: "succeeded",
      started_at: 2.minutes.ago,
      completed_at: 1.minute.ago,
      created_at: 2.minutes.ago
    )

    get root_path

    expect(response.body).to include("Recent imports, restores, and month operations", "Dismiss")

    patch recent_operations_preference_path

    expect(response).to redirect_to(root_path)
    expect(response).to have_http_status(:see_other)
    expect(provisioned.membership.reload.recent_operations_dismissed_through_at).to be_present

    get root_path
    expect(response.body).not_to include("Recent imports, restores, and month operations")

    travel 1.second do
      create(
        :operation_run,
        budget_workspace: provisioned.workspace,
        actor_membership: provisioned.membership,
        operation_type: "backup_v2_restore",
        state: "succeeded",
        started_at: Time.current,
        completed_at: Time.current
      )

      get root_path
      expect(response.body).to include("Recent imports, restores, and month operations", "Backup restore")
    end
  end

  it "keeps an active operation visible even when it started before dismissal" do
    provisioned = Identity::PersonalWorkspaceProvisioner.call(user: user)
    provisioned.membership.update!(recent_operations_dismissed_through_at: Time.current)
    create(
      :operation_run,
      budget_workspace: provisioned.workspace,
      actor_membership: provisioned.membership,
      operation_type: "commit_legacy_account_activity_import",
      state: "running",
      started_at: 1.minute.ago,
      created_at: 1.minute.ago
    )

    get root_path

    expect(response.body).to include("Account activity import", "1 in progress", "Dismiss completed")
  end
end
