require "rails_helper"

RSpec.describe Planning::OccurrenceSchedule do
  it "keeps an exact weekend-adjusted boundary occurrence attributed to its budget period" do
    workspace = create(:budget_workspace)
    period = create(:budget_period, budget_workspace: workspace, starts_on: Date.new(2026, 2, 1))
    template = create(:planning_template, budget_workspace: workspace)
    rule = RecurrenceRule.create!(
      planning_template: template,
      cadence: "monthly",
      interval_count: 1,
      anchor_on: Date.new(2026, 1, 28),
      day_one: 28,
      weekend_policy: "next_monday",
      starts_on: Date.new(2026, 1, 1)
    )

    occurrences = described_class.call(rule: rule, period: period)

    expect(occurrences.map(&:scheduled_on)).to eq([ Date.new(2026, 3, 2) ])
    expect(occurrences.map(&:slot_key)).to eq([ "day-one" ])
  end

  it "honors a biweekly interval anchored before the period" do
    workspace = create(:budget_workspace)
    period = create(:budget_period, budget_workspace: workspace, starts_on: Date.new(2026, 3, 1))
    template = create(:planning_template, budget_workspace: workspace)
    rule = RecurrenceRule.create!(
      planning_template: template,
      cadence: "weekly",
      interval_count: 2,
      anchor_on: Date.new(2026, 2, 20),
      weekend_policy: "none",
      starts_on: Date.new(2026, 2, 20)
    )

    expect(described_class.call(rule: rule, period: period).map(&:scheduled_on)).to eq(
      [ Date.new(2026, 3, 6), Date.new(2026, 3, 20) ]
    )
  end
end
