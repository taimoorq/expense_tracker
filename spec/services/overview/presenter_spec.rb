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
    expect(presenter.linked_entries_summary).to eq("2 linked month entries in April 2026 (0 paid).")
    expect(presenter.cashflow_available?).to be(true)
    expect(presenter.cashflow_chart_title).to eq("2026 cash flow graph")
    expect(presenter.cashflow_stat_cards.map { |item| item[:label] }).to eq([ "Months Included", "Income", "Outflow", "Leftover" ])
  end
end
