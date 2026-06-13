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
        due_soon_count: 3,
        missing_details_count: 1,
        paid_missing_actual_count: 0,
        linked_entries_count: 2,
        net_worth_total: -75,
        latest_snapshot: nil,
        financial_rhythm: "debt_payoff",
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
    expect(presenter.onboarding_steps.map { |step| step[:action_label] }).to eq([ "Review Accounts", "Set Up Recurring", "Open Plan and Edit", "Review Month" ])
    expect(presenter.continue_title).to eq("April 2026")
    expect(presenter.continue_badge_label).to eq("Current month")
    expect(presenter.current_month_leftover_value).to eq("$125.45")
    expect(presenter.current_month_leftover_class).to eq("text-emerald-700")
    expect(presenter.continue_stats.map { |item| item[:label] }).to eq([ "Leftover", "Entries", "Needs review" ])
    expect(presenter.continue_stats.last[:value_classes]).to eq("text-slate-900")
    expect(presenter.next_step_primary_action).to eq(label: "Open Plan and Edit", path: "/months/april/entries", turbo_frame: nil)
    expect(presenter.next_step_secondary_action).to eq(label: "Add Entry with Wizard", path: "/months/april/entries/new", turbo_frame: "entry_wizard_modal")
    expect(presenter.attention_items).to eq(
      [
        { label: "Still planned and due", count: 1 },
        { label: "Missing key details", count: 1 },
        { label: "Paid without actual", count: 0 }
      ]
    )
    expect(presenter.check_in_badge).to eq("Weekly check-in")
    expect(presenter.check_in_title).to eq("Keep April 2026 easy to trust")
    expect(presenter.check_in_status).to eq(label: "Review", classes: "bg-amber-100 text-amber-800")
    expect(presenter.check_in_win).to be_nil
    expect(presenter.check_in_items.map { |item| item[:label] }).to eq([ "Due now", "Due next 7 days", "Missing actuals", "Linked activity" ])
    expect(presenter.check_in_items.map { |item| item[:value] }).to eq([ 1, 3, 0, 2 ])
    expect(presenter.financial_rhythm_label).to eq("Debt payoff focus")
    expect(presenter.financial_rhythm_guidance).to include("credit card additions")
    expect(presenter.recurring_linked_summary).to eq("1 linked recurring transaction currently connected to accounts.")
    expect(presenter.recurring_breakdown_items.map { |item| item[:label] }).to eq([ "Pay schedules", "Subscriptions", "Monthly bills", "Payment plans" ])
    expect(presenter.net_worth_value_class).to eq("text-rose-700")
    expect(presenter.account_snapshot_cards.map { |item| item[:label] }).to eq([ "Net worth", "Latest snapshot" ])
    expect(presenter.account_flow_month_window).to eq("6")
    expect(presenter.account_flow_month_window_options).to include([ "Last 6 months", "6" ])
    expect(presenter.account_flow_available?).to be(true)
    expect(presenter.account_flow_summary_description).to eq("4 months included: January 2026 to April 2026.")
    expect(presenter.account_flow_stat_cards.map { |item| item[:label] }).to eq([ "Charged", "Paid to", "Tracked entries" ])
    expect(presenter.account_flow_summary_title).to eq("Linked account activity")
    expect(presenter.account_flow_chart_title).to eq("Linked Activity by Account")
    expect(presenter.account_flow_top_account_summary).to eq("Top activity: Checking")
    expect(presenter.account_flow_untracked_entries_summary).to eq("1 entry missing account detail")
    expect(presenter.linked_entries_summary).to eq("2 linked month entries in April 2026 (0 paid).")
    expect(presenter.cashflow_available?).to be(true)
    expect(presenter.cashflow_chart_title).to eq("2026 cash flow graph")
    expect(presenter.cashflow_stat_cards.map { |item| item[:label] }).to eq([ "Months Included", "Income", "Outflow", "Leftover" ])
  end

  it "uses calm positive states when a month has no review items" do
    user = create(:user)
    month = instance_double(
      BudgetMonth,
      label: "May 2026",
      month_on: Date.new(2026, 5, 1),
      calculated_leftover: 250
    )

    presenter = described_class.new(
      user: user,
      today: Date.new(2026, 5, 10),
      data: {
        accounts: [ instance_double(Account) ],
        current_month: month,
        current_month_entries: [ instance_double(ExpenseEntry) ],
        recent_months: [ month ],
        template_total: 1,
        linked_template_total: 1,
        review_attention_count: 0,
        linked_paid_entries_count: 1,
        template_counts: {
          pay_schedules: 1,
          subscriptions: 0,
          monthly_bills: 0,
          payment_plans: 0
        },
        due_planned_count: 0,
        due_soon_count: 0,
        missing_details_count: 0,
        paid_missing_actual_count: 0,
        linked_entries_count: 1,
        net_worth_total: 250,
        latest_snapshot: nil,
        financial_rhythm: "steady_income",
        account_flow_month_window: "3",
        account_flow_months_included: 1,
        account_flow_month_range_label: "May 2026",
        account_flow_payload: {
          labels: [],
          charged_values: [],
          paid_values: [],
          charged_total: 0,
          paid_total: 0,
          account_count: 0,
          tracked_entries_count: 0,
          untracked_entries_count: 0,
          top_account: nil
        },
        overview_cashflow_year: 2026,
        year_cashflow_payload: {
          links: [],
          nodes: [],
          month_count: 0,
          income_total: 0,
          outflow_total: 0,
          leftover_total: 0
        },
        next_step: {
          badge: "On track",
          title: "Keep the month current",
          description: "Make manual adjustments as the month changes.",
          primary_label: "Open Budget",
          primary_path: "/months/may",
          secondary_label: "Open Calendar",
          secondary_path: "/months/may/calendar"
        },
        onboarding_visible: false
      }
    )

    expect(presenter.check_in_status).to eq(label: "On track", classes: "bg-emerald-100 text-emerald-800")
    expect(presenter.check_in_win).to eq(
      title: "Small win",
      description: "Your attention queue is clear for now. A quick glance at upcoming plans is enough before you move on."
    )
    expect(presenter.continue_stats.last).to include(label: "Needs review", value: 0, value_classes: "text-emerald-700")
    expect(presenter.attention_queue_description).to eq("May 2026 has no urgent cleanup items right now.")
    expect(presenter.attention_queue_badge).to eq(label: "Clear", classes: "bg-emerald-100 text-emerald-800")
  end
end
