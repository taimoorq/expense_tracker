require "rails_helper"

RSpec.describe "Connected and manual financial workflows", type: :request do
  let(:user) { create(:user) }
  let!(:workspace) { Identity::NewWorkspaceSetup.call(user: user) }
  let(:membership) { workspace.workspace_memberships.sole }
  let!(:account) { create(:account, user: user, budget_workspace: workspace, kind: :checking) }

  before { sign_in user }

  def record(amount: "35.50", flow: "outflow", destination: nil, date: Date.current, key: SecureRandom.uuid)
    post activity_transactions_path, params: { transaction: { effective_on: date, description: "Household activity", amount: amount,
      flow_kind: flow, account_id: account.id, destination_account_id: destination&.id, idempotency_key: key } }
  end

  it "records, replays, matches, unmatches, and reverses manual activity without SimpleFIN" do
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month)
    entry = create(:expense_entry, user: user, budget_month: month, source_account: account, planned_amount: 35.50, actual_amount: nil, occurred_on: Date.current)
    Platform::TargetSync::ExpenseEntryWriter.call(entry: entry)
    record(key: "same-submit")
    expect(response).to have_http_status(:see_other)
    transaction = workspace.financial_transactions.state_posted.sole
    expect(transaction.account_postings.sole.amount).to eq(-35.50.to_d)
    record(key: "same-submit")
    expect(workspace.financial_transactions.count).to eq(1)
    item = workspace.budget_items.sole
    post activity_matches_path, params: { financial_transaction_id: transaction.id, budget_item_id: item.id, amount: "35.50" }
    expect(entry.reload).to be_paid
    expect(workspace.financial_transactions.state_posted.count).to eq(1)
    delete activity_match_path(transaction.budget_allocations.sole)
    expect(transaction.reload.budget_allocations).to be_empty
    expect(entry.reload).to be_planned
    delete activity_transaction_path(transaction)
    expect(transaction.reload).to be_state_reversed
  end

  it "records income and transfers with exact postings and rejects another user's account" do
    record(flow: "income")
    expect(workspace.financial_transactions.last.account_postings.sole.amount).to eq(35.50.to_d)
    destination = create(:account, user: user, budget_workspace: workspace, kind: :savings)
    record(flow: "transfer", destination: destination)
    expect(workspace.financial_transactions.flow_kind_transfer.sole.account_postings.sum(:amount)).to eq(0)
    other = create(:account)
    record(flow: "transfer", destination: other)
    expect(response).to have_http_status(:not_found)
    expect(workspace.financial_transactions.count).to eq(2)
  end

  it "blocks closed-period entry and leaves no partial postings" do
    create(:budget_period, budget_workspace: workspace, starts_on: Date.current.beginning_of_month, state: "closed")
    record
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Reopen the affected month")
    expect(workspace.financial_transactions).to be_empty
  end

  it "reviews unplanned imported activity without forcing a plan match" do
    transaction = create(:financial_transaction, budget_workspace: workspace, origin_kind: "institution_import")
    create(:account_posting, budget_workspace: workspace, financial_transaction: transaction, account: account)
    patch activity_transaction_path(transaction)
    expect(transaction.reload.reviewed_at).to be_present
    get activity_path(view: "review")
    expect(response.body).not_to include(transaction.description)
    get activity_path(view: "all")
    expect(response.body).to include("Unplanned · reviewed")
  end

  it "attaches and detaches matching bank evidence without changing the manual ledger" do
    record
    transaction = workspace.financial_transactions.sole
    mapping = create(:connected_account, account: account, bank_connection: create(:bank_connection, budget_workspace: workspace, actor_membership: membership))
    source = create(:provider_transaction, connected_account: mapping, amount: -35.50)
    get activity_path(view: "bank")
    expect(response.body).to include("Attach to existing transaction", "Household activity")
    patch provider_transaction_path(source), params: { choice: "existing", digest: source.content_digest, financial_transaction_id: transaction.id, return_to: "activity" }
    expect(response).to redirect_to(activity_path(view: "bank"))
    expect(source.reload).to have_attributes(financial_transaction_id: transaction.id, resolution_kind: "existing")
    expect(workspace.account_postings.count).to eq(1)
    patch provider_transaction_path(source), params: { choice: "undo" }
    expect(source.reload.financial_transaction).to be_nil
    expect(transaction.reload).to be_state_posted
    expect(workspace.account_postings.sum(:amount)).to eq(-35.50.to_d)
  end

  it "clears and undoes a reserved payment after disconnect, with one cash effect" do
    month = create(:budget_month, user: user, month_on: Date.current.beginning_of_month)
    mapping = create(:connected_account, account: account, import_transactions: false, bank_connection: create(:bank_connection, budget_workspace: workspace, actor_membership: membership))
    entry = create(:expense_entry, user: user, budget_month: month, source_account: account, planned_amount: 100, actual_amount: nil, occurred_on: Date.current)
    ExpenseEntries::Updater.call(expense_entry: entry, params: { actual_amount: 100 }, mark_as_paid: true)
    commitment = entry.payment_commitments.sole
    BankConnections::Disconnect.call(connection: mapping.bank_connection, membership: membership)
    2.times { post payment_settlements_path, params: { payment_commitment_id: commitment.id, cleared_on: Date.current, confirmed: "1" } }
    expect(commitment.reload.state).to eq("settled")
    transaction = workspace.financial_transactions.state_posted.sole
    expect(transaction.account_postings.sum(:amount)).to eq(-100)
    expect(transaction.budget_allocations.sole.amount).to eq(100)
    get activity_path(view: "payments")
    expect(response.body).to include("Undo clearing")
    delete payment_settlement_path(commitment.payment_settlements.sole)
    expect(commitment.reload.state).to eq("reserved")
    expect(transaction.reload).to be_state_reversed
    post payment_settlements_path, params: { payment_commitment_id: commitment.id, cleared_on: Date.current, confirmed: "1" }
    expect(workspace.financial_transactions.state_posted.count).to eq(1)
  end
end
