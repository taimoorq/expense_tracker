require "rails_helper"

RSpec.describe Budgeting::VisualDashboardPresenter do
  describe "derived chart data" do
    it "computes section totals, running values, and over-budget categories from provided entries" do
      user = create(:user)
      budget_month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
      create(:expense_entry,
        budget_month: budget_month,
        user: user,
        occurred_on: Date.new(2026, 3, 1),
        section: :income,
        category: "Paycheck",
        payee: "Employer",
        planned_amount: 3000,
        actual_amount: 3000,
        status: :paid)
      create(:expense_entry,
        budget_month: budget_month,
        user: user,
        occurred_on: Date.new(2026, 3, 5),
        section: :fixed,
        category: "Housing",
        payee: "Rent",
        planned_amount: 1000,
        actual_amount: 1200,
        status: :paid)
      create(:expense_entry,
        budget_month: budget_month,
        user: user,
        occurred_on: Date.new(2026, 3, 9),
        section: :variable,
        category: nil,
        payee: "Groceries",
        planned_amount: 200,
        actual_amount: 150,
        status: :paid)

      presenter = described_class.new(budget_month: budget_month, expense_entries: budget_month.expense_entries.to_a)

      expect(presenter.section_totals.to_h).to eq({ "fixed" => 1200.0, "variable" => 150.0 })
      expect(presenter.section_labels).to eq([ "Fixed", "Variable" ])
      expect(presenter.section_values).to eq([ 1200.0, 150.0 ])
      expect(presenter.line_labels).to eq([ "Mar 1", "Mar 5", "Mar 9" ])
      expect(presenter.line_values).to eq([ 3000.0, 1800.0, 1650.0 ])
      expect(presenter.cumulative_outflow_labels).to eq([ "Mar 5", "Mar 9" ])
      expect(presenter.cumulative_outflow_values).to eq([ 1200.0, 1350.0 ])
      expect(presenter.over_budget_labels).to eq([ "Housing" ])
      expect(presenter.over_budget_values).to eq([ 200.0 ])
      expect(presenter.income).to eq(3000.0)
      expect(presenter.leftover).to eq(1650.0)
      expect(presenter.savings_pct).to eq(55.0)
      expect(presenter.top_category).to eq([ "fixed", 1200.0 ])
    end


    it "reuses the graph portfolio with target forecast and posted-movement queries after cutover" do
      user = create(:user)
      checking = create(:account, user: user, name: "Checking")
      month = create(:budget_month, user: user, month_on: Date.new(2026, 3, 1), label: "March 2026")
      create(:expense_entry, budget_month: month, user: user, occurred_on: Date.new(2026, 3, 1), section: :income, category: "Paycheck", payee: "Employer", source_account: checking, planned_amount: 3000, actual_amount: 3000, status: :paid)
      create(:expense_entry, budget_month: month, user: user, occurred_on: Date.new(2026, 3, 5), section: :fixed, category: "Housing", payee: "Rent", source_account: checking, planned_amount: 1000, actual_amount: 1200, status: :paid)
      create(:expense_entry, budget_month: month, user: user, occurred_on: Date.new(2026, 3, 9), section: :variable, category: "Groceries", payee: "Market", source_account: checking, planned_amount: 200, actual_amount: 150, status: :paid)
      backfill = Platform::TargetBackfill::Runner.call(user: user)
      backfill.workspace.update!(target_writes_enabled: true, target_reads_enabled: true)

      presenter = described_class.new(budget_month: month, expense_entries: month.expense_entries.to_a)

      expect(presenter).to be_target_mode
      expect(presenter.calculation_version).to eq("target-v1")
      expect(presenter.section_totals).to eq({ "fixed" => 1200.0, "variable" => 200.0 })
      expect(presenter.line_values).to eq([ 3000.0, 1800.0, 1600.0 ])
      expect(presenter.cumulative_outflow_values).to eq([ 1200.0, 1400.0 ])
      expect(presenter.over_budget_labels).to eq([ "Housing" ])
      expect(presenter.over_budget_values).to eq([ 200.0 ])
      expect(presenter.leftover).to eq(1600.0)
      expect(presenter.sankey_payload[:outflow_total]).to eq(1400.to_d)
      expect(presenter.account_flow_payload).to include(
        labels: [ "Checking" ],
        charged_total: 1350.to_d,
        paid_total: 3000.to_d,
        tracked_entries_count: 3
      )
    end
  end
end
