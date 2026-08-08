require "rails_helper"

RSpec.describe Planning::UpcomingCommitments do
  it "builds a bounded 90-day target schedule with weekly exact totals" do
    workspace = create(:budget_workspace)
    account = create(:workspace_account, budget_workspace: workspace, name: "Checking")
    template = create(
      :planning_template,
      budget_workspace: workspace,
      name: "Power bill",
      kind: "bill",
      flow_kind: "outflow",
      default_amount: 125,
      source_account: account,
      active_from: Date.new(2026, 1, 1)
    )
    RecurrenceRule.create!(
      planning_template: template,
      cadence: "monthly",
      interval_count: 1,
      anchor_on: Date.new(2026, 1, 10),
      starts_on: Date.new(2026, 1, 10),
      day_one: 10,
      weekend_policy: "none"
    )
    period = create(:budget_period, budget_workspace: workspace, starts_on: Date.new(2026, 8, 1))
    item = create(:budget_item, budget_workspace: workspace, budget_period: period, scheduled_on: Date.new(2026, 8, 10))
    RecurringOccurrence.create!(
      budget_workspace: workspace,
      budget_period: period,
      planning_template: template,
      budget_item: item,
      scheduled_on: Date.new(2026, 8, 10),
      slot_key: "day-one",
      state: "materialized"
    )

    result = nil
    queries = count_select_queries do
      result = described_class.call(workspace: workspace, starts_on: Date.new(2026, 8, 7))
    end

    expect(queries).to be <= 10
    expect(result).to have_attributes(
      starts_on: Date.new(2026, 8, 7),
      ends_on: Date.new(2026, 11, 5),
      currency_code: "USD",
      calculation_version: "target-v1",
      maximum_week_total: 125.to_d
    )
    expect(result.rows.map(&:scheduled_on)).to eq(
      [ Date.new(2026, 8, 10), Date.new(2026, 9, 10), Date.new(2026, 10, 10) ]
    )
    expect(result.rows.first).to have_attributes(amount: 125.to_d, materialized: true, source_account: account)
    expect(result.weeks.sum(&:outflow)).to eq(375.to_d)
  end
end
