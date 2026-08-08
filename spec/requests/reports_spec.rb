require "rails_helper"

RSpec.describe "Reports", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "pairs plan-versus-actual and category graphs with accessible exact-value tables" do
    account = create(:account, user: user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1), label: "August 2026")
    create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      occurred_on: Date.new(2026, 8, 5),
      section: :fixed,
      category: "Housing",
      planned_amount: 1_200,
      actual_amount: 1_150,
      status: :paid
    )

    get reports_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Plan versus actual", "August 2026", "$1,200.00", "$1,150.00")
    expect(response.body).to include("Actual outflow by category", "Housing")
    expect(response.body).to include("Accessible values for the planned and actual monthly outflow chart")
    expect(response.body).to include('data-controller="chart"')
  end

  it "renders useful empty states without inventing zero-history graphs" do
    get reports_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No monthly history yet", "Paid outflows with categories will appear here")
  end

  it "uses one target calculation bundle after read cutover" do
    account = create(:account, user: user)
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1), label: "August 2026")
    create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      occurred_on: Date.new(2026, 8, 5),
      category: "Housing",
      planned_amount: 1_200,
      actual_amount: 1_150,
      status: :paid
    )
    backfill = Platform::TargetBackfill::Runner.call(user: user)
    backfill.workspace.update!(target_writes_enabled: true, target_reads_enabled: true)

    get reports_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Calculations: target-v1", "Housing", "$1,150.00")
  end

  it "uses frozen close totals and source lines even when late activity arrives" do
    account = create(:account, user: user, name: "Checking")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1), label: "August 2026")
    entry = create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      occurred_on: Date.new(2026, 8, 5),
      category: "Housing",
      payee: "Rent at close",
      planned_amount: 1_200,
      actual_amount: 1_150,
      status: :paid
    )
    backfill = Platform::TargetBackfill::Runner.call(user: user)
    workspace = backfill.workspace
    workspace.update!(target_writes_enabled: true, target_reads_enabled: true)
    period = mapped_target(workspace, month, BudgetPeriod)
    membership = workspace.workspace_memberships.find_by!(user: user)
    Budgeting::ClosePeriod.call(
      workspace: workspace,
      actor_membership: membership,
      budget_period: period,
      idempotency_key: "close-for-report"
    )
    original_transaction = mapped_target(workspace, entry, FinancialTransaction)
    original_transaction.update_columns(description: "Renamed after close", gross_amount: 1_175)
    category = workspace.categories.find_by!(name: "Housing")
    late = create(
      :financial_transaction,
      budget_workspace: workspace,
      category: category,
      description: "Late housing import",
      gross_amount: 999,
      effective_on: Date.new(2026, 8, 20)
    )
    create(:account_posting, budget_workspace: workspace, financial_transaction: late, account: account, amount: -999)

    get reports_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Closed snapshot", "$1,150.00")
    expect(response.body).not_to include("$2,149.00", "$1,175.00")

    get report_sources_path(category: "Housing", starts_on: "2026-08-01", ends_on: "2026-08-31")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Rent at close", "Closed snapshot", "Exact total", "$1,150.00")
    expect(response.body).not_to include("Renamed after close", "Late housing import", "$999.00")

    get budget_month_month_close_path(month)
    expect(response.body).to include("Records frozen with this close", "Late transactions stay in Activity")
  end

  def mapped_target(workspace, source, target_class)
    mapping = workspace.legacy_record_mappings.find_by!(
      legacy_record_type: source.class.name,
      legacy_record_id: source.id,
      target_record_type: target_class.name
    )
    target_class.find(mapping.target_record_id)
  end
end
