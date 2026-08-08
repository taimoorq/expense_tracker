require "rails_helper"

RSpec.describe "Operation status", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "shows bounded durable progress and a safe support reference" do
    provisioned = Identity::PersonalWorkspaceProvisioner.call(user: user)
    operation = create(
      :operation_run,
      budget_workspace: provisioned.workspace,
      actor_membership: provisioned.membership,
      operation_type: "backup_v2_restore",
      state: "running",
      progress_current: 40,
      progress_total: 100,
      progress_label: "Restoring transactions",
      started_at: Time.current,
      retryable: true
    )

    get operation_run_path(operation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Backup restore", "In progress", "Restoring transactions")
    expect(response.body).to include("aria-valuenow=\"40\"", operation.id.delete("-").first(12).upcase)
    expect(response.body).to include("data-controller=\"operation-poll\"")
  end

  it "does not expose another user's or internal migration operation" do
    other = create(:user)
    provisioned = Identity::PersonalWorkspaceProvisioner.call(user: other)
    external_operation = create(:operation_run, budget_workspace: provisioned.workspace, operation_type: "backup_v2_restore")

    get operation_run_path(external_operation)
    expect(response).to have_http_status(:not_found)

    sign_in user
    own = Identity::PersonalWorkspaceProvisioner.call(user: user)
    internal_operation = create(:operation_run, budget_workspace: own.workspace, operation_type: "target_model_backfill")

    get operation_run_path(internal_operation)
    expect(response).to have_http_status(:not_found)
  end
end
