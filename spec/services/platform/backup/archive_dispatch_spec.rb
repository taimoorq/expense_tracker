require "rails_helper"

RSpec.describe Platform::Backup::ArchiveDispatch do
  include ActiveJob::TestHelper

  def configuration
    Platform::Backup::ArchiveConfiguration.new(
      environment: {
        "BACKUP_STORAGE_DRIVER" => "local",
        "BACKUP_LOCAL_ROOT" => "/tmp/finance-tracking-backups",
        "BACKUP_ENCRYPTION_KEY" => Base64.strict_encode64("k" * 32)
      }
    )
  end

  def eligible_user
    create(:user).tap do |user|
      workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
      workspace.update!(target_writes_enabled: true, target_reads_enabled: true)
    end
  end

  it "creates a durable archive obligation and queues its job" do
    user = eligible_user

    result = described_class.call(user: user, configuration: configuration)

    expect(result.archive).to have_attributes(
      trigger: "manual",
      state: "pending",
      storage_adapter: "local",
      encryption_key_id: "primary"
    )
    expect(result.operation.job_arguments).to eq([ result.archive.id ])
    expect(enqueued_jobs.map { |job| job.fetch(:job) }).to include(Platform::Backup::ArchiveJob)
  end

  it "creates a checksummed legacy archive obligation before target cutover" do
    user = create(:user)
    workspace = Platform::TargetBackfill::WorkspaceBootstrap.call(user: user).workspace

    result = described_class.call(user: user, configuration: configuration)

    expect(result.archive.payload_format_version).to eq("1")
    expect(result.archive.budget_workspace).to eq(workspace)
  end

  it "deduplicates a scheduled slot" do
    user = eligible_user
    workspace = user.legacy_owned_budget_workspace
    schedule = create(:backup_schedule, budget_workspace: workspace, creator_membership: workspace.workspace_memberships.sole)
    slot = Time.utc(2026, 8, 27, 2)

    first = described_class.call(user: user, schedule: schedule, scheduled_for: slot, configuration: configuration)
    second = described_class.call(user: user, schedule: schedule, scheduled_for: slot, configuration: configuration)

    expect(second.archive).to eq(first.archive)
    expect(schedule.backup_archives.count).to eq(1)
  end

  it "requires an active owner" do
    user = eligible_user
    user.workspace_memberships.sole.update!(role: "editor")

    expect do
      described_class.call(user: user, configuration: configuration)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end
end
