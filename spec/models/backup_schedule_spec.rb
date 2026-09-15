require "rails_helper"

RSpec.describe BackupSchedule do
  it "enforces cadence-specific fields" do
    schedule = build(:backup_schedule, cadence: "weekly", weekday: nil)

    expect(schedule).not_to be_valid
    expect(schedule.errors[:weekday]).to include("is required for weekly backups")
  end

  it "requires the creator to belong to the workspace" do
    schedule = build(:backup_schedule, creator_membership: create(:workspace_membership))

    expect(schedule).not_to be_valid
    expect(schedule.errors[:creator_membership]).to include("must belong to the same workspace")
  end

  it "enables and pauses with coherent next-run state" do
    schedule = create(:backup_schedule, local_minute_of_day: 9 * 60)
    after = Time.utc(2026, 8, 26, 12)

    schedule.enable!(after: after)
    expect(schedule).to have_attributes(state: "enabled", next_run_at: Time.utc(2026, 8, 27, 9))

    schedule.pause!
    expect(schedule).to have_attributes(state: "paused", next_run_at: nil)
  end
end
