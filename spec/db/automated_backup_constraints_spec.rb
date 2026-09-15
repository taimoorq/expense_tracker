require "rails_helper"

RSpec.describe "automated backup database constraints" do
  it "rejects a schedule creator from another workspace below Active Record" do
    schedule = create(:backup_schedule)
    other_membership = create(:workspace_membership)

    expect do
      ActiveRecord::Base.connection.execute(<<~SQL)
        UPDATE backup_schedules
        SET creator_membership_id = '#{other_membership.id}'
        WHERE id = '#{schedule.id}'
      SQL
    end.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  it "rejects duplicate scheduled slots below Active Record" do
    schedule = create(:backup_schedule)
    slot = Time.utc(2026, 8, 27, 2)
    create(
      :backup_archive,
      budget_workspace: schedule.budget_workspace,
      actor_membership: schedule.creator_membership,
      trigger: "scheduled",
      backup_schedule: schedule,
      scheduled_for: slot
    )

    expect do
      create(
        :backup_archive,
        budget_workspace: schedule.budget_workspace,
        actor_membership: schedule.creator_membership,
        trigger: "scheduled",
        backup_schedule: schedule,
        scheduled_for: slot
      )
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
