require "rails_helper"

RSpec.describe Platform::Backup::DispatchDueSchedulesJob, type: :job do
  include ActiveJob::TestHelper

  around do |example|
    original = ENV.to_h.slice("BACKUP_STORAGE_DRIVER", "BACKUP_LOCAL_ROOT", "BACKUP_ENCRYPTION_KEY")
    ENV["BACKUP_STORAGE_DRIVER"] = "local"
    ENV["BACKUP_LOCAL_ROOT"] = "/tmp/finance-tracking-backups"
    ENV["BACKUP_ENCRYPTION_KEY"] = Base64.strict_encode64("k" * 32)
    example.run
  ensure
    %w[BACKUP_STORAGE_DRIVER BACKUP_LOCAL_ROOT BACKUP_ENCRYPTION_KEY].each { |key| ENV.delete(key) }
    original.each { |key, value| ENV[key] = value }
  end

  def due_schedule(now)
    user = create(:user)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.update!(target_writes_enabled: true, target_reads_enabled: true)
    create(
      :backup_schedule,
      budget_workspace: workspace,
      creator_membership: workspace.workspace_memberships.sole,
      state: "enabled",
      next_run_at: now - 2.hours,
      cadence: "daily",
      local_minute_of_day: 120
    )
  end

  it "dispatches one archive for a due slot and advances beyond the scan time" do
    now = Time.utc(2026, 8, 26, 12)
    schedule = due_schedule(now)

    described_class.perform_now(now)
    described_class.perform_now(now)

    expect(schedule.backup_archives.count).to eq(1)
    expect(schedule.reload.next_run_at).to be > now
    expect(schedule.last_attempted_at).to eq(now)
  end

  it "advances without a burst when another archive is active" do
    now = Time.utc(2026, 8, 26, 12)
    schedule = due_schedule(now)
    create(
      :backup_archive,
      budget_workspace: schedule.budget_workspace,
      actor_membership: schedule.creator_membership
    )

    described_class.perform_now(now)

    expect(schedule.backup_archives.count).to eq(0)
    expect(schedule.reload.next_run_at).to be > now
  end
end
