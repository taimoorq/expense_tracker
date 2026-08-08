require "rails_helper"

RSpec.describe Reports::OverviewQuery do
  it "keeps the target report query count bounded as the month count grows" do
    user = create(:user)
    12.times do |index|
      month_on = Date.new(2026, 1, 1).next_month(index)
      month = create(:budget_month, user: user, month_on: month_on, label: month_on.strftime("%B %Y"))
      create(:expense_entry, user: user, budget_month: month, occurred_on: month_on, section: :fixed, category: "Housing", planned_amount: 1_000)
    end
    backfill = Platform::TargetBackfill::Runner.call(user: user)
    backfill.workspace.update!(target_writes_enabled: true, target_reads_enabled: true)

    queries = count_select_queries { described_class.call(user: user.reload) }

    expect(queries).to be <= 20
  end
end
