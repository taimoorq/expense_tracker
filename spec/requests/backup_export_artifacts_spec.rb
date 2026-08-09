require "rails_helper"

RSpec.describe "Backup export artifacts", type: :request do
  include ActiveJob::TestHelper

  it "lets the owner download a ready artifact from its operation status" do
    owner = create(:user)
    Platform::TargetBackfill::Runner.call(user: owner)
    dispatched = Platform::Backup::V2::ExportDispatch.call(user: owner, scopes: [ "accounts" ])
    clear_enqueued_jobs
    Platform::Backup::V2::ExportJob.perform_now(dispatched.operation.id, dispatched.artifact.id)
    sign_in owner

    get operation_run_path(dispatched.operation)
    expect(response.body).to include("Download backup")

    get backup_export_artifact_path(dispatched.artifact)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.headers.fetch("Content-Disposition")).to include("attachment")
    expect(JSON.parse(response.body)).to include("version" => 2)
  end

  it "does not expose another user's generated backup" do
    owner = create(:user)
    workspace = Platform::TargetBackfill::Runner.call(user: owner).workspace
    dispatched = Platform::Backup::V2::ExportDispatch.call(
      user: owner,
      scopes: Platform::Backup::V2::Preview::FINANCIAL_SCOPES
    )
    clear_enqueued_jobs
    Platform::Backup::V2::ExportJob.perform_now(dispatched.operation.id, dispatched.artifact.id)
    sign_in create(:user)

    get backup_export_artifact_path(dispatched.artifact)

    expect(response).to have_http_status(:not_found)
    expect(workspace.backup_export_artifacts.sole).to be_available
  end
end
