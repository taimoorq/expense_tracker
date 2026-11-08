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

    artifact_queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      artifact_queries << sql if sql.start_with?("SELECT") && sql.include?('FROM "backup_export_artifacts"')
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      get operation_run_path(dispatched.operation)
    end
    expect(response.body).to include("Download backup")
    expect(artifact_queries).not_to be_empty
    expect(artifact_queries).to all(start_with('SELECT "backup_export_artifacts"."id" FROM'))

    get backup_export_artifact_path(dispatched.artifact)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.headers.fetch("Content-Disposition")).to include("attachment")
    expect(JSON.parse(response.body)).to include("version" => 2)
  end

  it "lists checkpoint metadata without loading its encrypted payload" do
    owner = create(:user)
    checkpoint = Platform::Backup::CreateCheckpoint.call(user: owner, scopes: [ "preferences" ])
    sign_in owner
    checkpoint_queries = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql]
      checkpoint_queries << sql if sql.start_with?("SELECT") && sql.include?('FROM "restore_checkpoints"')
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      get backup_restore_path
    end

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(checkpoint.id.delete("-").first(12).upcase)
    expect(checkpoint_queries).not_to be_empty
    expect(checkpoint_queries.join).not_to include('"encrypted_payload"', '"restore_checkpoints".*')
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
