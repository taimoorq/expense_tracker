require "rails_helper"

RSpec.describe "Activity", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  it "shows one review record for unmatched imported activity and exposes stable tabs" do
    account = create(:account, user: user, name: "Checking")
    activity_import = create(:account_activity_import, user: user, account: account)
    create(
      :account_activity,
      user: user,
      account: account,
      account_activity_import: activity_import,
      description: "Corner market",
      amount: 24.50,
      account_delta: -24.50
    )

    get activity_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Actual money movement", "Needs review", "Unmatched", "Corner market", "$24.50")
    expect(response.body).to include('aria-current="page"')
    expect(response.body.scan("Corner market").size).to eq(1)
  end

  it "keeps import evidence in its own view" do
    account = create(:account, user: user)
    create(:account_activity_import, user: user, account: account, original_filename: "checking.csv")

    get activity_path(view: "imports")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Import history", "checking.csv", "Evidence")
  end

  it "keeps tab counts exact when the visible history is capped" do
    account = create(:account, user: user)
    activity_import = create(:account_activity_import, user: user, account: account)
    105.times do |index|
      create(
        :account_activity,
        user: user,
        account: account,
        account_activity_import: activity_import,
        expense_entry: nil,
        transaction_on: Date.new(2026, 8, 1) + index.days,
        fingerprint: "activity-#{index}"
      )
    end

    get activity_path(view: "unmatched")

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/Unmatched.*?105/m)
    expect(response.body).to include("Showing the newest 100 records")
    expect(response.body.scan("data-activity-row").count).to eq(100)
  end

  it "matches and unmatches imported actuals through the target command while preserving legacy rollback parity" do
    account = create(:account, user: user, name: "Checking")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    entry = create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      category: "Groceries",
      payee: "Market",
      planned_amount: 50,
      status: :planned,
      occurred_on: Date.new(2026, 8, 5)
    )
    activity_import = create(:account_activity_import, user: user, account: account)
    activity = create(
      :account_activity,
      user: user,
      account: account,
      account_activity_import: activity_import,
      description: "Market purchase",
      amount: 42.50,
      account_delta: -42.50,
      transaction_on: Date.new(2026, 8, 5)
    )
    backfill = Platform::TargetBackfill::Runner.call(user: user)
    workspace = backfill.workspace
    workspace.update!(target_writes_enabled: true, target_reads_enabled: true)
    transaction = mapped_target(workspace, activity, FinancialTransaction)
    item = mapped_target(workspace, entry, BudgetItem)

    get activity_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Market purchase", "Choose plan item", "Market", "Match")

    expect do
      post activity_matches_path, params: {
        financial_transaction_id: transaction.id,
        budget_item_id: item.id,
        amount: "42.50"
      }
    end.to change(workspace.budget_allocations, :count).by(1)

    expect(response).to redirect_to(activity_path(view: "review"))
    expect(activity.reload.expense_entry).to eq(entry)
    allocation = workspace.budget_allocations.sole
    expect(workspace.audit_events.where(action: "match", entity_id: allocation.id)).to exist

    expect do
      delete activity_match_path(allocation)
    end.to change(workspace.budget_allocations, :count).by(-1)

    expect(activity.reload.expense_entry).to be_nil
    expect(workspace.audit_events.where(action: "unmatch", entity_id: allocation.id)).to exist
  end

  it "keeps target reconciliation endpoints unavailable before read cutover" do
    post activity_matches_path, params: {
      financial_transaction_id: SecureRandom.uuid,
      budget_item_id: SecureRandom.uuid,
      amount: "1.00"
    }

    expect(response).to have_http_status(:not_found)
  end

  it "keeps target account movement drill-downs scoped to exact dates and direction" do
    account = create(:account, user: user, name: "Checking")
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      payee: "Inside range outflow",
      occurred_on: Date.new(2026, 8, 8),
      status: :paid,
      actual_amount: 20
    )
    create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      payee: "Outside range outflow",
      occurred_on: Date.new(2026, 8, 2),
      status: :paid,
      actual_amount: 30
    )
    create(
      :expense_entry,
      user: user,
      budget_month: month,
      source_account: account,
      payee: "Inside range income",
      section: :income,
      occurred_on: Date.new(2026, 8, 8),
      status: :paid,
      actual_amount: 100
    )
    backfill = Platform::TargetBackfill::Runner.call(user: user)
    backfill.workspace.update!(target_writes_enabled: true, target_reads_enabled: true)

    get activity_path(
      view: "all",
      account_id: account.id,
      starts_on: "2026-08-07",
      ends_on: "2026-08-09",
      direction: "outgoing"
    )

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Inside range outflow", "Filtered to", "Checking", "outgoing")
    expect(response.body).not_to include("Outside range outflow", "Inside range income")
  end

  it "keeps a quarantined paid entry visible until the user assigns its real account" do
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    entry = create(
      :expense_entry,
      user: user,
      budget_month: month,
      payee: "Historical utility payment",
      occurred_on: Date.new(2026, 8, 6),
      status: :paid,
      actual_amount: 84.25
    )
    account = create(:account, user: user, name: "Household checking")
    backfill = Platform::TargetBackfill::Runner.call(user: user)
    workspace = backfill.workspace
    discrepancy = workspace.migration_discrepancies.find_by!(
      legacy_record_type: "ExpenseEntry",
      legacy_record_id: entry.id,
      code: "paid_entry_missing_account"
    )

    expect(backfill).not_to be_success

    get activity_path(view: "review")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Historical utility payment", "Account needed", "Choose the real account", "No account is inferred")

    patch migration_discrepancy_resolution_path(discrepancy), params: { account_id: account.id }

    expect(response).to redirect_to(activity_path(view: "review"))
    expect(entry.reload.source_account).to eq(account)
    expect(discrepancy.reload).to be_status_resolved
    transaction = mapped_target(workspace, entry, FinancialTransaction)
    expect(transaction.account_postings.sole).to have_attributes(account_id: account.id, amount: -84.25.to_d)
    expect(workspace.reload.target_backfilled_at).to be_present
    expect(workspace).not_to be_target_reads_enabled
    expect(workspace.audit_events.where(action: "resolve_migration_discrepancy", entity_id: discrepancy.id)).to exist
  end

  it "routes a quarantined entry to account setup when no account can be selected" do
    month = create(:budget_month, user: user, month_on: Date.new(2026, 8, 1))
    create(
      :expense_entry,
      user: user,
      budget_month: month,
      payee: "Historical internet payment",
      occurred_on: Date.new(2026, 8, 6),
      status: :paid,
      actual_amount: 78
    )
    Platform::TargetBackfill::Runner.call(user: user)

    get activity_path(view: "review")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Historical internet payment", "Add an account first")
    expect(response.body).to include(new_account_path, "Create the real account, then return here")
    expect(response.body).not_to include("Choose the real account")
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
