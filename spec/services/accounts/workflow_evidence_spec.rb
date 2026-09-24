require "rails_helper"

RSpec.describe "Workflow evidence integrity" do
  let(:user) { create(:user) }
  let!(:workspace) { Identity::NewWorkspaceSetup.call(user: user) }
  let(:membership) { workspace.workspace_memberships.sole }
  let(:account) { create(:account, user: user, budget_workspace: workspace) }

  def manual(amount:, date:, description: "Reviewed spending")
    Accounts::RecordManualTransaction.call(workspace: workspace, actor_membership: membership, idempotency_key: SecureRandom.uuid,
      attributes: { account: account, amount: amount, effective_on: date, description: description, flow_kind: "outflow" }).value
  end

  it "separates posting-month actuals, partial allocation remainders, and cross-month matches" do
    september = create(:budget_period, budget_workspace: workspace, starts_on: Date.new(2026, 9, 1))
    october = create(:budget_period, budget_workspace: workspace, starts_on: Date.new(2026, 10, 1))
    transaction = manual(amount: 100, date: september.starts_on + 10.days)
    item = create(:budget_item, budget_workspace: workspace, budget_period: october, planned_amount: 60)
    create(:budget_allocation, budget_workspace: workspace, budget_item: item, financial_transaction: transaction, amount: 60)
    manual(amount: 25, date: september.starts_on + 11.days)
    create(:financial_transaction, budget_workspace: workspace, effective_on: september.starts_on, gross_amount: 500, state: "pending")
    create(:financial_transaction, budget_workspace: workspace, effective_on: september.starts_on, gross_amount: 500, state: "reversed")

    expect(Budgeting::RecordedActuals.call(period: september)).to include("outflow" => 125.to_d, "unallocated_outflow" => 65.to_d)
    expect(Budgeting::PeriodSummary.call(period: september).actual_outflow).to eq(0)
    expect(Budgeting::PeriodSummary.call(period: october).actual_outflow).to eq(60)
    expect(Budgeting::RecordedActuals.call(period: october).fetch("outflow")).to eq(0)
  end

  it "freezes recorded totals and preserves review, duplicate evidence, and onboarding through backup restore" do
    month = create(:budget_month, user: user, budget_workspace: workspace, month_on: Date.new(2026, 9, 1))
    entry = create(:expense_entry, user: user, budget_month: month, source_account: account, planned_amount: 100, occurred_on: Date.new(2026, 9, 15))
    Platform::TargetSync::ExpenseEntryWriter.call(entry: entry)
    transaction = manual(amount: 25, date: Date.new(2026, 9, 16))
    transaction.update!(reviewed_at: Time.current)
    mapping = create(:connected_account, account: account, bank_connection: create(:bank_connection, budget_workspace: workspace, actor_membership: membership))
    source = create(:provider_transaction, connected_account: mapping, amount: -25, posted_at: Time.utc(2026, 9, 16, 15))
    BankConnections::AttachExistingTransaction.call(source: source, transaction: transaction, membership: membership, digest: source.content_digest)
    membership.update!(onboarding_path: "manual", onboarding_recurring_skipped_at: Time.current)
    close = Budgeting::ClosePeriod.call(workspace: workspace, actor_membership: membership, budget_period: workspace.budget_periods.sole, idempotency_key: "close-evidence").value
    expect(close.recorded_totals.fetch("outflow").to_d).to eq(25)
    expect(close.actual_outflow).to eq(0)
    expect(close.calculation_version).to eq("target-v2-recorded")

    scopes = Platform::Backup::V2::Preview::FINANCIAL_SCOPES + [ "preferences" ]
    payload = Platform::Backup::V2::Exporter.new(user: user, scopes: scopes).as_json
    destination = create(:user)
    result = Platform::UserDataImport.new(user: destination, payload: payload, scopes: scopes).call
    expect(result).to include(success: true)
    restored = BudgetWorkspace.find_by!(legacy_owner_user: destination)
    expect(restored.month_closes.sole.recorded_totals.fetch("outflow").to_d).to eq(25)
    expect(restored.provider_transactions.sole.resolution_kind).to eq("existing")
    expect(restored.provider_transactions.sole.financial_transaction.reviewed_at).to be_present
    expect(restored.bank_connections.sole).to have_attributes(status: "disconnected", automatic_refresh: false, encrypted_access_url: nil)
    expect(restored.workspace_memberships.sole.onboarding_path).to eq("manual")
    expect(restored.workspace_memberships.sole.onboarding_recurring_skipped_at).to be_present
    expect(restored.financial_transactions.state_posted.sum(:gross_amount)).to eq(25)
  end

  it "uses each canonical CSV or bank movement once and excludes pending and reversed evidence" do
    import = create(:account_activity_import, user: user, account: account, commit_idempotency_key: SecureRandom.hex(32), file_digest: SecureRandom.hex(32), rows_count: 3, imported_count: 3)
    (7..9).each do |month|
      create(:account_activity, user: user, account: account, account_activity_import: import, description: "Cloud storage", category: "Software", activity_type: "Sale", row_number: month, fingerprint: SecureRandom.hex(32), transaction_on: Date.new(2026, month, 8), amount: 12, account_delta: -12)
    end
    Platform::TargetSync::AccountActivityImportWriter.call(legacy_import: import)
    mapping = create(:connected_account, account: account, bank_connection: create(:bank_connection, budget_workspace: workspace, actor_membership: membership))
    duplicate = create(:provider_transaction, connected_account: mapping, description: "Cloud storage", amount: -12, posted_at: Time.utc(2026, 9, 8, 14))
    existing = workspace.financial_transactions.find_by!(effective_on: Date.new(2026, 9, 8))
    BankConnections::AttachExistingTransaction.call(source: duplicate, transaction: existing, membership: membership, digest: duplicate.content_digest)
    create(:provider_transaction, connected_account: mapping, description: "Cloud storage", amount: -12, pending: true, posted_at: nil)
    evidence = Accounts::ActivityEvidence.call(account: account)
    expect(evidence.size).to eq(3)
    candidate = Accounts::RecurringCandidates::Detector.new(account: account).call.sole
    expect(candidate).to include(count: 3, months_seen: 3, estimated_amount: 12.to_d)
    expect(evidence.map(&:source_label)).to include("Statement CSV · SimpleFIN evidence")
  end

  it "blocks close consistently while prior-month payments remain reserved" do
    period = create(:budget_period, budget_workspace: workspace, starts_on: Date.new(2026, 9, 1))
    workspace.payment_commitments.create!(account: account, amount: 30, currency_code: "USD", initiated_on: Date.new(2026, 8, 31), reserved_at: Time.current)
    readiness = Budgeting::CloseReadiness.call(period: period)
    expect(readiness).not_to be_can_close
    expect(readiness.reserved_count).to eq(1)
    expect { Budgeting::ClosePeriod.call(workspace: workspace, actor_membership: membership, budget_period: period, idempotency_key: "blocked-close") }.to raise_error(Budgeting::ClosePeriod::InvalidState)
    expect(period.reload).to be_state_open
    expect(workspace.month_closes).to be_empty
  end

  it "requires reopening the recorded month for matching and unmatching across planning months" do
    september = create(:budget_period, budget_workspace: workspace, starts_on: Date.new(2026, 9, 1))
    october = create(:budget_period, budget_workspace: workspace, starts_on: Date.new(2026, 10, 1))
    transaction = manual(amount: 100, date: september.starts_on + 10.days)
    item = create(:budget_item, budget_workspace: workspace, budget_period: october, planned_amount: 100)
    allocation = Accounts::MatchTransaction.call(workspace: workspace, actor_membership: membership, transaction: transaction, budget_item: item, amount: 50, idempotency_key: "first-match").value
    september.update!(state: "closed")

    expect { Accounts::MatchTransaction.call(workspace: workspace, actor_membership: membership, transaction: transaction, budget_item: item, amount: 50, idempotency_key: "late-match") }.to raise_error(Accounts::MatchTransaction::InvalidMatch, /Reopen/)
    expect { Accounts::UnmatchTransaction.call(workspace: workspace, actor_membership: membership, allocation: allocation, idempotency_key: "late-unmatch") }.to raise_error(Accounts::UnmatchTransaction::InvalidMatch, /Reopen/)
    expect(transaction.budget_allocations.sum(:amount)).to eq(50)
    september.update!(state: "reopened")
    Accounts::UnmatchTransaction.call(workspace: workspace, actor_membership: membership, allocation: allocation, idempotency_key: "reopened-unmatch")
    expect(transaction.budget_allocations).to be_empty
  end

  it "rejects a plan with a different flow before changing allocation evidence" do
    transaction = manual(amount: 100, date: Date.new(2026, 9, 15))
    item = create(:budget_item, budget_workspace: workspace, flow_kind: "income")
    expect { Accounts::MatchTransaction.call(workspace: workspace, actor_membership: membership, transaction: transaction, budget_item: item, amount: 100, idempotency_key: "wrong-flow") }.to raise_error(Accounts::MatchTransaction::InvalidMatch, /same money movement/)
    expect(transaction.budget_allocations).to be_empty
  end

  it "requires attaching bank evidence when a plan already has a direct manual transaction" do
    month = create(:budget_month, user: user, budget_workspace: workspace, month_on: Date.new(2026, 9, 1))
    entry = create(:expense_entry, user: user, budget_month: month, source_account: account, planned_amount: 25, occurred_on: Date.new(2026, 9, 15))
    Platform::TargetSync::ExpenseEntryWriter.call(entry: entry)
    transaction = manual(amount: 25, date: Date.new(2026, 9, 15))
    Accounts::LegacyMatchBridge.match(workspace: workspace, actor_membership: membership, transaction: transaction, budget_item: workspace.budget_items.sole, amount: 25, idempotency_key: "manual-plan")
    mapping = create(:connected_account, account: account, bank_connection: create(:bank_connection, budget_workspace: workspace, actor_membership: membership))
    source = create(:provider_transaction, connected_account: mapping, amount: -25, posted_at: Time.utc(2026, 9, 15, 14))
    expect { BankConnections::AcceptTransaction.call(source: source, membership: membership, digest: source.content_digest, entry: entry) }.to raise_error(ArgumentError, /Attach the bank evidence/)
    expect(workspace.financial_transactions.state_posted.count).to eq(1)
    BankConnections::AttachExistingTransaction.call(source: source.reload, transaction: transaction, membership: membership, digest: source.content_digest)
    expect(workspace.financial_transactions.state_posted.sum(:gross_amount)).to eq(25)
    expect(transaction.reload.budget_allocations.sum(:amount)).to eq(25)
  end
end
