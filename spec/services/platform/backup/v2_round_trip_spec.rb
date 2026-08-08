require "rails_helper"

RSpec.describe "Backup V2 round trip" do
  let(:scopes) { Platform::Backup::V2::Preview::FINANCIAL_SCOPES + [ "preferences" ] }

  it "restores a checksum-protected relationship bundle into distinct empty workspaces without key collisions" do
    source_user = create(:user, preferred_month_view: "breakdown")
    account = create(:account, user: source_user, kind: :checking, name: "Checking")
    create(:account_snapshot, account: account, balance: 1_000, recorded_on: Date.new(2026, 8, 1))
    month = create(:budget_month, user: source_user, month_on: Date.new(2026, 8, 1), label: "August 2026")
    create(
      :expense_entry,
      user: source_user,
      budget_month: month,
      source_account: account,
      category: "Housing",
      planned_amount: 125,
      actual_amount: 120,
      status: :paid,
      occurred_on: Date.new(2026, 8, 5)
    )
    activity_import = create(:account_activity_import, user: source_user, account: account)
    create(:account_activity, user: source_user, account: account, account_activity_import: activity_import)
    source_workspace = Platform::TargetBackfill::Runner.call(user: source_user).workspace
    payload = Platform::Backup::V2::Exporter.new(user: source_user, scopes: scopes).as_json

    first_user = create(:user)
    first = Platform::UserDataImport.new(user: first_user, payload: payload, scopes: scopes).call
    second_user = create(:user)
    second = Platform::UserDataImport.new(user: second_user, payload: payload, scopes: scopes).call

    expect(first).to include(success: true)
    expect(second).to include(success: true)
    first_workspace = BudgetWorkspace.find_by!(legacy_owner_user: first_user)
    second_workspace = BudgetWorkspace.find_by!(legacy_owner_user: second_user)
    expect(first_workspace.id).not_to eq(source_workspace.id)
    expect(second_workspace.id).not_to be_in([ source_workspace.id, first_workspace.id ])
    expect(first_workspace.accounts.sole.name).to eq("Checking")
    expect(first_workspace.balance_observations.sole.account).to eq(first_workspace.accounts.sole)
    expect(first_workspace.budget_items.sole.budget_period).to eq(first_workspace.budget_periods.sole)
    expect(first_workspace.financial_transactions.count).to eq(source_workspace.financial_transactions.count)
    expect(first_workspace.account_postings.count).to eq(source_workspace.account_postings.count)
    expect(first_workspace.budget_allocations.sole.budget_item).to eq(first_workspace.budget_items.sole)
    expect(first_workspace).to be_target_reads_enabled
    expect(first_workspace).to be_target_writes_enabled
    expect(first_user.budget_months.sole.month_on).to eq(Date.new(2026, 8, 1))
    expect(first_user.expense_entries.sole).to have_attributes(planned_amount: 125.to_d, actual_amount: 120.to_d, status: "paid")
    expect(first_user.account_snapshots.sole.balance).to eq(1_000.to_d)
    expect(first_user.account_activity_imports.count).to eq(1)
    expect(first_user.account_activities.count).to eq(1)
    expect(first_user.reload.preferred_month_view).to eq("breakdown")
    expect(first_workspace.data_transfer_runs.operation_restore.state_succeeded.count).to eq(1)
    expect(first_workspace.audit_events.where(action: "backup_restore")).to exist

    replay = Platform::UserDataImport.new(user: first_user, payload: payload, scopes: scopes).call
    expect(replay).to include(success: true)
    expect(first_workspace.data_transfer_runs.operation_restore.state_succeeded.count).to eq(1)
    expect(first_workspace.accounts.count).to eq(1)

    restored_entry = first_user.expense_entries.sole
    expect(ExpenseEntries::Updater.call(expense_entry: restored_entry, params: { planned_amount: 150 }, mark_as_paid: false)).to be(true)
    mapping = first_workspace.legacy_record_mappings.find_by!(
      legacy_record_type: "ExpenseEntry",
      legacy_record_id: restored_entry.id,
      target_record_type: "BudgetItem"
    )
    expect(BudgetItem.find(mapping.target_record_id).planned_amount).to eq(150.to_d)
  end

  it "rejects a changed payload before creating destination data" do
    source_user = create(:user)
    create(:account, user: source_user)
    Platform::TargetBackfill::Runner.call(user: source_user)
    payload = Platform::Backup::V2::Exporter.new(user: source_user, scopes: scopes).as_json.deep_dup
    payload[:workspace][:name] = "Tampered"
    destination_user = create(:user)

    result = Platform::UserDataImport.new(user: destination_user, payload: payload, scopes: scopes).call

    expect(result).to eq(success: false, error: "The backup checksum does not match its contents.")
    expect(BudgetWorkspace.find_by(legacy_owner_user: destination_user)).to be_nil
    expect(destination_user.accounts).to be_empty
  end

  it "does not replace a non-empty destination" do
    source_user = create(:user)
    create(:account, user: source_user)
    Platform::TargetBackfill::Runner.call(user: source_user)
    payload = Platform::Backup::V2::Exporter.new(user: source_user, scopes: scopes).as_json
    destination_user = create(:user)
    existing_account = create(:account, user: destination_user, name: "Keep me")

    result = Platform::UserDataImport.new(user: destination_user, payload: payload, scopes: scopes).call

    expect(result).to include(success: false)
    expect(result[:error]).to include("requires an empty destination")
    expect(existing_account.reload.name).to eq("Keep me")
  end

  it "serializes the cipher and KDF contract independently from payload version" do
    payload = {
      format: Platform::UserDataExport::FORMAT_NAME,
      version: 2,
      exported_at: Time.current.iso8601,
      scopes: [],
      workspace: {},
      data: {},
      payload_checksum: "0" * 64
    }

    encoded = Platform::UserDataBackupCodec.encode(payload: payload, password: "very-secret")
    envelope = JSON.parse(encoded)
    decoded = Platform::UserDataBackupCodec.decode(source: encoded, password: "very-secret")

    expect(envelope).to include(
      "version" => 2,
      "cipher" => "aes-256-gcm",
      "kdf" => include("algorithm" => "pbkdf2-hmac", "digest" => "sha256", "iterations" => 210_000)
    )
    expect(decoded).to include(success: true)
    expect(decoded[:payload][:version]).to eq(2)
  end

  it "projects restored target templates into the active recurring workflow atomically" do
    source_user = create(:user)
    checking = create(:account, user: source_user, name: "Checking", kind: :checking)
    card = create(:account, user: source_user, name: "Visa", kind: :credit_card)
    create(:pay_schedule, user: source_user, name: "Payroll", cadence: :semimonthly, amount: 2_000, first_pay_on: Date.new(2026, 1, 1), day_of_month_one: 1, day_of_month_two: 15, linked_account: checking)
    create(:subscription, user: source_user, name: "Streaming", amount: 20, due_day: 8, linked_account: checking)
    create(:monthly_bill, user: source_user, name: "Insurance", default_amount: 300, due_day: 10, billing_frequency: :quarterly, billing_months: [ 1, 4, 7, 10 ], linked_account: checking)
    create(:payment_plan, user: source_user, name: "Loan", total_due: 2_000, amount_paid: 200, monthly_target: 100, due_day: 12, linked_account: checking)
    create(:credit_card, user: source_user, name: "Visa payment", minimum_payment: 75, due_day: 20, linked_account: card, payment_account: checking)
    Platform::TargetBackfill::Runner.call(user: source_user)
    payload = Platform::Backup::V2::Exporter.new(user: source_user, scopes: scopes).as_json
    destination = create(:user)

    result = Platform::UserDataImport.new(user: destination, payload: payload, scopes: scopes).call

    expect(result).to include(success: true)
    expect(destination.pay_schedules.sole).to have_attributes(name: "Payroll", cadence: "semimonthly", day_of_month_two: 15)
    expect(destination.subscriptions.sole).to have_attributes(name: "Streaming", due_day: 8)
    expect(destination.monthly_bills.sole).to have_attributes(name: "Insurance", billing_frequency: "quarterly", billing_months: [ 1, 4, 7, 10 ])
    expect(destination.payment_plans.sole).to have_attributes(name: "Loan", total_due: 2_000.to_d, amount_paid: 200.to_d)
    expect(destination.credit_cards.sole).to have_attributes(name: "Visa payment", linked_account_id: destination.accounts.find_by!(name: "Visa").id)
  end

  it "round trips immutable close totals and source snapshots" do
    source = create(:user)
    account = create(:account, user: source)
    month = create(:budget_month, user: source, month_on: Date.new(2026, 8, 1))
    create(
      :expense_entry,
      user: source,
      budget_month: month,
      source_account: account,
      category: "Housing",
      payee: "Rent",
      planned_amount: 1_200,
      actual_amount: 1_150,
      status: :paid,
      occurred_on: Date.new(2026, 8, 5)
    )
    source_workspace = Platform::TargetBackfill::Runner.call(user: source).workspace
    period = source_workspace.budget_periods.sole
    Budgeting::ClosePeriod.call(
      workspace: source_workspace,
      actor_membership: source_workspace.workspace_memberships.sole,
      budget_period: period,
      idempotency_key: "backup-close"
    )
    payload = Platform::Backup::V2::Exporter.new(user: source, scopes: scopes).as_json
    destination = create(:user)

    result = Platform::UserDataImport.new(user: destination, payload: payload, scopes: scopes).call

    expect(result).to include(success: true)
    restored = destination.reload.legacy_owned_budget_workspace
    close = restored.month_closes.sole
    expect(close.report_summary.actual_outflow).to eq(1_150.to_d)
    expect(close.item_snapshots.sole).to have_attributes(category_snapshot: "Housing", actual_amount: 1_150.to_d)
    expect(close.transaction_snapshots.sole).to have_attributes(description_snapshot: "Rent", gross_amount: 1_150.to_d)
  end
end
