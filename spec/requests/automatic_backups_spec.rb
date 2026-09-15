require "rails_helper"
require "tmpdir"

RSpec.describe "Automatic backups", type: :request do
  include ActiveJob::TestHelper

  around do |example|
    Dir.mktmpdir("finance-tracking-backups") do |directory|
      original = ENV.to_h.slice("BACKUP_STORAGE_DRIVER", "BACKUP_LOCAL_ROOT", "BACKUP_ENCRYPTION_KEY")
      ENV["BACKUP_STORAGE_DRIVER"] = "local"
      ENV["BACKUP_LOCAL_ROOT"] = directory
      ENV["BACKUP_ENCRYPTION_KEY"] = Base64.strict_encode64("k" * 32)
      example.run
    ensure
      %w[BACKUP_STORAGE_DRIVER BACKUP_LOCAL_ROOT BACKUP_ENCRYPTION_KEY].each { |key| ENV.delete(key) }
      original.each { |key, value| ENV[key] = value }
    end
  end

  def eligible_user
    create(:user).tap do |user|
      workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
      workspace.update!(target_writes_enabled: true, target_reads_enabled: true)
    end
  end

  def schedule_params(state: "enabled")
    {
      backup_schedule: {
        state: state,
        cadence: "weekly",
        time_zone: "Eastern Time (US & Canada)",
        local_time: "03:30",
        weekday: "1",
        day_of_month: "1",
        retention_count: "14"
      }
    }
  end

  it "lets an owner configure and pause a schedule" do
    user = eligible_user
    sign_in user

    get backup_restore_path
    expect(response.body).to include("Scheduled workspace backups")

    patch backup_schedule_path, params: schedule_params

    schedule = user.legacy_owned_budget_workspace.backup_schedule
    expect(response).to redirect_to(backup_restore_path)
    expect(schedule).to have_attributes(
      state: "enabled",
      cadence: "weekly",
      weekday: 1,
      day_of_month: nil,
      local_minute_of_day: 210,
      retention_count: 14
    )
    expect(schedule.next_run_at).to be_present

    patch backup_schedule_path, params: schedule_params(state: "paused").deep_merge(
      backup_schedule: { lock_version: schedule.lock_version }
    )
    expect(schedule.reload).to have_attributes(state: "paused", next_run_at: nil)
  end

  it "lets a legacy workspace enable automatic backups without forcing target cutover" do
    user = create(:user)
    workspace = Platform::TargetBackfill::WorkspaceBootstrap.call(user: user).workspace
    sign_in user

    patch backup_schedule_path, params: schedule_params

    expect(response).to redirect_to(backup_restore_path)
    expect(workspace.reload).not_to be_target_reads_enabled
    expect(workspace.backup_schedule).to be_state_enabled
  end

  it "queues a run-now archive and serves the verified file only to its owner" do
    owner = eligible_user
    sign_in owner

    post run_now_backup_schedule_path
    archive = owner.legacy_owned_budget_workspace.backup_archives.sole
    expect(response).to redirect_to(operation_run_path(archive.operation_run))
    clear_enqueued_jobs
    Platform::Backup::ArchiveJob.perform_now(archive.operation_run_id, archive.id)

    get backup_archive_path(archive)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.headers.fetch("Content-Disposition")).to include("attachment")
    expect(JSON.parse(response.body)).to include(
      "format" => Platform::Backup::ArchiveCodec::FORMAT_NAME,
      "key_id" => "primary"
    )

    sign_out owner
    sign_in create(:user)
    get backup_archive_path(archive)
    expect(response).to have_http_status(:not_found)
  end

  it "does not let a non-owner manage automatic backups" do
    user = eligible_user
    user.workspace_memberships.sole.update!(role: "editor")
    sign_in user

    patch backup_schedule_path, params: schedule_params

    expect(response).to have_http_status(:not_found)
    expect(user.legacy_owned_budget_workspace.backup_schedule).to be_nil
  end
end
