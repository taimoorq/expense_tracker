require "rails_helper"

RSpec.describe "SimpleFIN lifecycle" do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { create(:user) }
  let!(:account) { create(:account, user: user, kind: :checking) }
  let!(:month) { create(:budget_month, user: user, month_on: Date.new(2026, 9, 1)) }
  let!(:entry) { create(:expense_entry, user: user, budget_month: month, source_account: account, planned_amount: 350, actual_amount: nil, occurred_on: Date.new(2026, 9, 20)) }
  let(:workspace) { Platform::TargetBackfill::Runner.call(user: user).workspace.tap { |w| w.update!(target_reads_enabled: true, target_writes_enabled: true) } }
  let(:membership) { workspace.workspace_memberships.sole }
  let(:connection) { create(:bank_connection, budget_workspace: workspace, actor_membership: membership) }
  let!(:mapping) { create(:connected_account, bank_connection: connection, account: account.reload) }

  around { |example| travel_to(Time.utc(2026, 9, 23, 18)) { example.run } }

  def accept(balance, dispositions: {}, coverage: {})
    BankConnections::AcceptBalance.call(mapping: mapping, membership: membership, balance_id: balance.id,
      mapping_version: mapping.reload.mapping_version, dispositions: dispositions, coverage: coverage, confirmed: true)
  end

  def record_payment(amount = 350)
    expect(ExpenseEntries::Updater.call(expense_entry: entry.reload, params: { actual_amount: amount },
      mark_as_paid: true)).to be(true), entry.errors.full_messages.to_sentence
    entry.payment_commitments.sole
  end

  def position
    Accounts::BankPosition.new(account: account.reload).result
  end

  it "reserves a recorded payment and settles it once against bank evidence" do
    initial = create(:provider_balance, connected_account: mapping, balance: 3200, reported_at: 2.days.ago, fetched_at: 2.days.ago)
    accept(initial)
    payment = record_payment
    expect(position.current_balance).to eq(2850)
    expect(position.projected_balance).to eq(2850)
    later = create(:provider_balance, connected_account: mapping, balance: 2850, reported_at: 1.hour.ago)
    accept(later, dispositions: { payment.id => "included" })
    expect(position.current_balance).to eq(2850)
    source = create(:provider_transaction, connected_account: mapping, posted_at: 2.hours.ago)
    transaction = BankConnections::AcceptTransaction.call(source: source, membership: membership, digest: source.content_digest, entry: entry)
    expect(payment.reload.state).to eq("settled")
    expect(position.current_balance).to eq(2850)
    expect(transaction.budget_allocations.sole.amount).to eq(350)
    expect { BankConnections::AcceptTransaction.call(source: source, membership: membership, digest: source.content_digest, entry: entry) }.not_to change(AccountPosting, :count)
    expect(Accounts::Summary.new(user: user).call[:net_worth_total]).to eq(2850)
    BankConnections::UnacceptTransaction.call(source: source.reload, membership: membership)
    expect(payment.reload.state).to eq("reserved")
    expect(position.current_balance).to eq(2850)
    expect(transaction.reload.state).to eq("reversed")
    BankConnections::AcceptTransaction.call(source: source.reload, membership: membership, digest: source.content_digest, entry: entry.reload)
    expect(position.current_balance).to eq(2850)
  end

  it "retains the unfunded remainder of a partial recorded payment" do
    initial = create(:provider_balance, connected_account: mapping, balance: 1000, reported_at: 2.days.ago, fetched_at: 2.days.ago)
    accept(initial)
    record_payment(100)
    expect(position.current_balance).to eq(900)
    expect(position.planned_delta).to eq(-250)
    expect(position.projected_balance).to eq(650)
  end

  it "automatically advances a selected bank source only while payment coverage is unambiguous" do
    accept(create(:provider_balance, connected_account: mapping, balance: 3200, reported_at: 2.days.ago, fetched_at: 2.days.ago))
    next_balance = create(:provider_balance, connected_account: mapping, balance: 3300, reported_at: 1.hour.ago, fetched_at: 30.minutes.ago)
    BankConnections::AutoAcceptBalance.call(mapping: mapping, membership: membership, generation: connection.credential_generation)
    expect(next_balance.reload.state).to eq("accepted")
    expect(position.current_balance).to eq(3300)
    record_payment
    ambiguous = create(:provider_balance, connected_account: mapping, balance: 2950, reported_at: 10.minutes.ago)
    BankConnections::AutoAcceptBalance.call(mapping: mapping, membership: membership, generation: connection.credential_generation)
    expect(ambiguous.reload.state).to eq("reported")
    expect(position.current_balance).to eq(2950)
  end

  it "requires explicit coverage of date-only activity on the balance date" do
    transaction = Accounts::TransactionBuilder.new(workspace: workspace, attributes: { account: account.reload, effective_on: Date.current, description: "Cash payment", amount: 25, flow_kind: "outflow" }).call
    balance = create(:provider_balance, connected_account: mapping)
    expect { accept(balance) }.to raise_error(ArgumentError, /Recorded activity changed/)
    accept(balance, coverage: { transaction.id => "outside" })
    expect(position.current_balance).to eq(2825)
    another = Accounts::TransactionBuilder.new(workspace: workspace, attributes: { account: account.reload, effective_on: Date.current, description: "Unreviewed", amount: 1, flow_kind: "outflow" }).call
    expect(position.balance_available).to be(false)
    expect(another).to be_persisted
  end

  it "pairs transfer sides without inventing an arrival and counts the plan once" do
    destination = create(:account, user: user, budget_workspace: workspace, kind: :savings)
    peer_mapping = create(:connected_account, bank_connection: connection, account: destination)
    debit = create(:provider_transaction, connected_account: mapping, posted_at: 2.days.ago)
    credit = create(:provider_transaction, connected_account: peer_mapping, amount: 350, posted_at: 1.day.ago)
    transaction = BankConnections::AcceptTransaction.call(source: debit, membership: membership, digest: debit.content_digest, transfer_account: destination)
    expect(transaction.account_postings.count).to eq(1)
    paired = BankConnections::AcceptTransaction.call(source: credit, membership: membership, digest: credit.content_digest, counterpart: debit.reload)
    expect(paired).to eq(transaction)
    expect(transaction.account_postings.sum(:amount)).to eq(0)
    expect(transaction.account_postings.order(:effective_at).pluck(:effective_at)).to eq([ debit.posted_at, credit.posted_at ])
    before_arrival = Accounts::TargetDetailQuery.call(account: destination, as_of: debit.posted_at.to_date)
    expect(before_arrival[:recent_activity][:canonical_rows]).to be_empty
    after_arrival = Accounts::TargetDetailQuery.call(account: destination)
    expect(after_arrival[:recent_activity][:canonical_rows].sole.effective_on).to eq(credit.posted_at.to_date)
  end

  it "adds a positive card credit to net worth instead of reporting it as debt" do
    account.update!(kind: :credit_card)
    balance = create(:provider_balance, connected_account: mapping, balance: 125, reported_at: 1.hour.ago)
    accept(balance)
    expect(position.current_balance).to eq(125)
    expect(Accounts::Summary.new(user: user).call[:net_worth_total]).to eq(125)
    expect(Accounts::TargetDetailQuery.call(account: account)[:credit_card_progress][:current_debt]).to eq(0)
  end

  it "rejects corrections in a closed month and cross-workspace access" do
    source = create(:provider_transaction, connected_account: mapping)
    workspace.budget_periods.find_by!(starts_on: month.month_on).update!(state: "closed")
    expect { BankConnections::AcceptTransaction.call(source: source, membership: membership, digest: source.content_digest) }.to raise_error(ArgumentError, /Reopen/)
    other = create(:workspace_membership)
    expect { BankConnections::Disconnect.call(connection: connection, membership: other) }.to raise_error(Identity::WorkspaceAccess::NotAuthorized)
  end

  it "restores portable bank evidence, timing and reservations without credentials or schedules" do
    initial = create(:provider_balance, connected_account: mapping, balance: 3200, reported_at: 2.days.ago, fetched_at: 2.days.ago)
    accept(initial)
    payment = record_payment
    latest = create(:provider_balance, connected_account: mapping, reported_at: 1.hour.ago)
    accept(latest, dispositions: { payment.id => "outside" })
    source = create(:provider_transaction, connected_account: mapping, amount: -100, transacted_at: 40.minutes.ago, posted_at: 30.minutes.ago)
    BankConnections::AcceptTransaction.call(source: source, membership: membership, digest: source.content_digest, entry: entry)
    scopes = Platform::Backup::V2::Preview::FINANCIAL_SCOPES
    payload = Platform::Backup::V2::Exporter.new(user: user, scopes: scopes).as_json
    expect(payload.to_json).not_to include("private-test-token", "encrypted_access_url", "claim_fingerprint")
    expect(Platform::Backup::V2::StagingValidator.new(payload: payload, scopes: scopes).call).to include(success: true)
    destination = create(:user)
    result = Platform::UserDataImport.new(user: destination, payload: payload, scopes: scopes).call
    expect(result).to include(success: true), result.inspect
    restored = destination.reload.legacy_owned_budget_workspace
    expect(restored.bank_connections.sole).to have_attributes(status: "disconnected", encrypted_access_url: nil, automatic_refresh: false)
    expect(restored.payment_commitments.sole.expense_entry).to eq(destination.expense_entries.sole)
    expect(restored.payment_commitments.sole.outstanding_amount).to eq(250)
    restored_source = restored.provider_transactions.sole
    expect(restored_source.expense_entry).to eq(destination.expense_entries.sole)
    expect(restored_source.financial_transaction.transacted_at).to eq(source.transacted_at)
    expect(restored.payment_settlements.sole.financial_transaction).to eq(restored_source.financial_transaction)
    expect(Accounts::BankPosition.new(account: destination.accounts.sole).result.current_balance).to eq(position.current_balance)
  end
  it "keeps overdue plans in the forecast after accepting a newer bank balance" do
    balance = create(:provider_balance, connected_account: mapping, balance: 1000, reported_at: 1.hour.ago)
    accept(balance)
    expect(position.projected_balance).to eq(650)
    expect(position.planned_delta).to eq(-350)
  end

  it "matches and unmatches bank activity from Activity without creating a duplicate manual posting" do
    source = create(:provider_transaction, connected_account: mapping)
    transaction = BankConnections::AcceptTransaction.call(source: source, membership: membership, digest: source.content_digest)
    item = workspace.budget_items.sole
    outcome = Accounts::LegacyMatchBridge.match(workspace: workspace, actor_membership: membership, transaction: transaction,
      budget_item: item, amount: 350, idempotency_key: "bank-match")
    expect(source.reload.expense_entry).to eq(entry)
    expect(entry.reload).to be_paid
    expect(transaction.account_postings.count).to eq(1)
    Accounts::LegacyMatchBridge.unmatch(workspace: workspace, actor_membership: membership, allocation: outcome.value, idempotency_key: "bank-unmatch")
    expect(source.reload.expense_entry).to be_nil
    expect(entry.reload).to be_planned
  end

  it "edits and cancels unsettled reservations without leaving phantom cash deductions" do
    balance = create(:provider_balance, connected_account: mapping, balance: 1000, reported_at: 2.days.ago, fetched_at: 2.days.ago)
    accept(balance)
    payment = record_payment
    expect(ExpenseEntries::Updater.call(expense_entry: entry.reload, params: { actual_amount: 300 }, mark_as_paid: false)).to be(true)
    expect(payment.reload.outstanding_amount).to eq(300)
    expect(position.current_balance).to eq(700)
    expect(ExpenseEntries::Updater.call(expense_entry: entry.reload, params: { status: "planned", actual_amount: nil }, mark_as_paid: false)).to be(true)
    expect(payment.reload.state).to eq("cancelled")
    expect(position.current_balance).to eq(1000)
    expect(position.projected_balance).to eq(650)
  end
end
