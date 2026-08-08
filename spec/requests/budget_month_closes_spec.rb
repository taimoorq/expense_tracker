require "rails_helper"

RSpec.describe "Budget month close", type: :request do
  let(:user) { create(:user) }
  let(:month) { create(:budget_month, user: user, month_on: Date.new(2026, 8, 1), label: "August 2026") }

  before { sign_in user }

  it "previews, closes, protects, and reopens a target-backed month" do
    create(:expense_entry, user: user, budget_month: month, planned_amount: 125)
    result = Platform::TargetBackfill::Runner.call(user: user)
    workspace = result.workspace
    workspace.update!(target_writes_enabled: true, target_reads_enabled: true)
    period = mapped_period(workspace)

    get budget_month_month_close_path(month)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Summary that will be frozen", "Calculation version target-v1", "$125.00", "Ready")

    post budget_month_month_close_path(month)

    expect(response).to redirect_to(budget_month_path(month))
    expect(period.reload).to be_state_closed
    expect(period.month_closes.state_closed.count).to eq(1)
    close = period.month_closes.state_closed.sole
    expect(close.item_snapshots.count).to eq(1)
    expect(close.item_snapshots.sole).to have_attributes(planned_amount: 125.to_d, actual_amount: 0.to_d, remaining_amount: 125.to_d)

    get budget_month_path(month)

    expect(response.body).to include("Review Close", "This month is closed", "Read only")
    expect(response.body).not_to include(">Add Entry<")

    get budget_month_tab_path(month, "entries")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("read-only")
    expect(response.body).not_to include("Add Paychecks", "Add Subscriptions", "Add Monthly Bills")

    create_result = ExpenseEntries::Creator.call(
      user: user,
      budget_month: month,
      expense_entry_params: {
        occurred_on: month.month_on + 10.days,
        section: "variable",
        category: "Groceries",
        payee: "Market",
        planned_amount: "50.00",
        status: "planned",
        source_file: "manual"
      },
      planning_template_params: {},
      recurring_link_token: nil
    )
    expect(create_result).not_to be_success
    expect(create_result.expense_entry.errors.full_messages.to_sentence).to include("Reopen August 2026")

    patch reopen_budget_month_month_close_path(month)

    expect(response).to redirect_to(budget_month_path(month))
    expect(period.reload).to be_state_reopened
    expect(period.month_closes.state_superseded.count).to eq(1)
  end

  it "does not expose target close controls before the read cutover" do
    Platform::TargetBackfill::Runner.call(user: user)

    get budget_month_month_close_path(month)

    expect(response).to have_http_status(:not_found)
  end

  def mapped_period(workspace)
    mapping = workspace.legacy_record_mappings.find_by!(
      legacy_record_type: "BudgetMonth",
      legacy_record_id: month.id,
      target_record_type: "BudgetPeriod"
    )
    BudgetPeriod.find(mapping.target_record_id)
  end
end
