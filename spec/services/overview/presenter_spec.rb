require "rails_helper"

RSpec.describe Overview::Presenter do
  it "exposes overview page data through presenter methods" do
    user = create(:user)
    month = create(:budget_month, user:, month_on: Date.current.beginning_of_month, label: Date.current.strftime("%B %Y"))

    presenter = described_class.new(user: user)

    expect(presenter.current_month).to eq(month)
    expect(presenter.recent_months).to include(month)
    expect(presenter.next_step).to include(:title, :primary_label, :primary_path)
    expect(presenter.to_h).to include(:current_month, :next_step, :onboarding_visible)
  end

  it "provides structured onboarding and action data for the view" do
    user = create(:user)
    month = instance_double(
      BudgetMonth,
      label: "April 2026",
      month_on: Date.new(2026, 4, 1),
      calculated_leftover: 125.45
    )

    presenter = described_class.new(
      user: user,
      today: Date.new(2026, 4, 15),
      data: {
        accounts: [ instance_double(Account) ],
        current_month: month,
        current_month_entries: [ instance_double(ExpenseEntry), instance_double(ExpenseEntry) ],
        recent_months: [ month ],
        template_total: 3,
        linked_template_total: 1,
        review_attention_count: 2,
        linked_paid_entries_count: 0,
        template_counts: {
          pay_schedules: 0,
          subscriptions: 1,
          monthly_bills: 1,
          payment_plans: 1
        },
        due_planned_count: 1,
        missing_details_count: 1,
        paid_missing_actual_count: 0,
        linked_entries_count: 2,
        net_worth_total: -75,
        latest_snapshot: nil,
        account_flow_month_window: "6",
        account_flow_months_included: 4,
        account_flow_month_range_label: "January 2026 to April 2026",
        account_flow_payload: {
          labels: [ "Checking", "Visa" ],
          charged_values: [ 800, 250 ],
          paid_values: [ 2_000, 300 ],
          charged_total: 1_050,
          paid_total: 2_300,
          account_count: 2,
          tracked_entries_count: 5,
          untracked_entries_count: 1,
          top_account: {
            name: "Checking",
            charged_total: 800.0,
            paid_total: 2_000.0
          }
        },
        overview_cashflow_year: 2026,
        year_cashflow_payload: {
          links: [ { source: "Income", target: "Bills", value: 100 } ],
          nodes: [],
          month_count: 1,
          income_total: 100,
          outflow_total: 75,
          leftover_total: 25
        },
        next_step: {
          badge: "Needs review",
          title: "Review 2 attention items",
          description: "Some entries need a second look.",
          primary_label: "Open Plan and Edit",
          primary_path: "/months/april/entries",
          secondary_label: "Add Entry with Wizard",
          secondary_path: "/months/april/entries/new",
          secondary_turbo_frame: "entry_wizard_modal"
        },
        onboarding_visible: true
      }
    )

    expect(presenter.onboarding_status).to eq(label: "In progress", classes: "bg-indigo-100 text-indigo-800")
    expect(presenter.onboarding_steps.map { |step| step[:badge_label] }).to eq([ "Done", "In progress", "Done", "In progress" ])
    expect(presenter.continue_title).to eq("April 2026")
    expect(presenter.continue_badge_label).to eq("Current month")
    expect(presenter.current_month_leftover_value).to eq("$125.45")
    expect(presenter.current_month_leftover_class).to eq("text-emerald-700")
    expect(presenter.continue_stats.map { |item| item[:label] }).to eq([ "Leftover", "Entries", "Needs review" ])
    expect(presenter.next_step_primary_action).to eq(label: "Open Plan and Edit", path: "/months/april/entries", turbo_frame: nil)
    expect(presenter.next_step_secondary_action).to eq(label: "Add Entry with Wizard", path: "/months/april/entries/new", turbo_frame: "entry_wizard_modal")
    expect(presenter.attention_items).to eq(
      [
        { label: "Still planned and due", count: 1 },
        { label: "Missing key details", count: 1 },
        { label: "Paid without actual", count: 0 }
      ]
    )
    expect(presenter.recurring_linked_summary).to eq("1 linked recurring transaction currently connected to accounts.")
    expect(presenter.recurring_breakdown_items.map { |item| item[:label] }).to eq([ "Pay schedules", "Subscriptions", "Monthly bills", "Payment plans" ])
    expect(presenter.net_worth_value_class).to eq("text-rose-700")
    expect(presenter.account_snapshot_cards.map { |item| item[:label] }).to eq([ "Net worth", "Latest snapshot" ])
    expect(presenter.account_flow_month_window).to eq("6")
    expect(presenter.account_flow_month_window_options).to include([ "Last 6 months", "6" ])
    expect(presenter.account_flow_available?).to be(true)
    expect(presenter.account_flow_summary_description).to eq("4 months included: January 2026 to April 2026.")
    expect(presenter.account_flow_stat_cards.map { |item| item[:label] }).to eq([ "Charged", "Paid to", "Tracked entries" ])
    expect(presenter.account_flow_chart_title).to eq("Charged vs Paid To by Account")
    expect(presenter.account_flow_top_account_summary).to eq("Top activity: Checking")
    expect(presenter.account_flow_untracked_entries_summary).to eq("1 entry missing account detail")
    expect(presenter.linked_entries_summary).to eq("2 linked month entries in April 2026 (0 paid).")
    expect(presenter.cashflow_available?).to be(true)
    expect(presenter.cashflow_chart_title).to eq("2026 cash flow graph")
    expect(presenter.cashflow_stat_cards.map { |item| item[:label] }).to eq([ "Months Included", "Income", "Outflow", "Leftover" ])
  end
end
