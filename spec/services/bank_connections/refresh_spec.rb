require "rails_helper"

RSpec.describe BankConnections::Refresh do
  include ActiveSupport::Testing::TimeHelpers
  let(:workspace) { create(:budget_workspace, target_writes_enabled: true, target_reads_enabled: true) }
  let(:connection) { create(:bank_connection, budget_workspace: workspace) }
  let(:mapping) { create(:connected_account, bank_connection: connection, import_transactions: true, provider_account_id: "checking") }
  let(:client) { instance_double(BankConnections::Simplefin::Client) }
  let(:payload) { { "accounts" => [ { "id" => "checking", "conn_id" => "institution-1", "name" => "Checking", "currency" => "USD", "balance" => "900.00", "balance-date" => 1.hour.ago.to_i, "transactions" => [ { "id" => "p1", "amount" => "-100.00", "description" => "Payment", "posted" => 2.hours.ago.to_i } ] } ] } }

  def refresh
    mapping
    @refresh ||= BankConnections::RefreshDispatch.call(connection: connection, membership: connection.actor_membership, initial: true)
  end

  it "deduplicates replay and repeated provider data and preserves source time" do
    allow(client).to receive(:accounts).and_return(payload)
    described_class.new(refresh: refresh, client: client).call
    expect(refresh.reload.state).to eq("succeeded")
    balance = mapping.provider_balances.sole
    expect(balance.reported_at.to_i).to eq(payload["accounts"][0]["balance-date"])
    expect(mapping.provider_transactions.sole.state).to eq("review")
    expect { described_class.new(refresh: refresh, client: client).call }.not_to change(ProviderBalance, :count)
    expect(client).to have_received(:accounts).once
    @refresh = nil
    described_class.new(refresh: refresh, client: client).call
    expect(mapping.provider_balances.count).to eq(1)
    expect(mapping.provider_transactions.count).to eq(1)
  end

  it "saves a valid balance even when that account's transactions are malformed" do
    payload["accounts"][0]["transactions"][0]["amount"] = "NaN"
    allow(client).to receive(:accounts).and_return(payload)
    described_class.new(refresh: refresh, client: client).call
    expect(refresh.reload.state).to eq("partial")
    expect(mapping.provider_balances.count).to eq(1)
    expect(mapping.provider_transactions.count).to eq(0)
    expect(mapping.reload.transactions_through_at).to be_nil
  end

  it "promotes a pending provider record to posted review without duplicating or accepting it" do
    transaction = payload["accounts"][0]["transactions"][0]
    transaction["pending"] = true
    transaction.delete("posted")
    allow(client).to receive(:accounts).and_return(payload)
    described_class.new(refresh: refresh, client: client).call
    source = mapping.provider_transactions.sole
    expect(source).to be_pending
    transaction["pending"] = false
    transaction["posted"] = 1.hour.ago.to_i
    @refresh = nil
    described_class.new(refresh: refresh, client: client).call
    expect(mapping.provider_transactions.sole).to have_attributes(id: source.id, pending: false, state: "review", financial_transaction_id: nil)
  end

  it "fences responses after disconnect without destroying saved evidence" do
    run = refresh
    allow(client).to receive(:accounts) do
      BankConnections::Disconnect.call(connection: connection, membership: connection.actor_membership)
      payload
    end
    described_class.new(refresh: run, client: client).call
    expect(run.reload.state).to eq("cancelled")
    expect(mapping.provider_balances).to be_empty
    expect(connection.reload.encrypted_access_url).to be_nil
  end

  it "charges failed attempts to the rolling request allowance" do
    allow(client).to receive(:accounts).and_raise(BankConnections::Simplefin::Client::Error.new(:temporary, "Try later"))
    expect { described_class.new(refresh: refresh, client: client).call }.to raise_error(BankConnections::Simplefin::Client::Error)
    expect(connection.reload.request_times.size).to eq(1)
    expect(refresh.reload.state).to eq("pending")
    connection.update!(request_times: Array.new(12) { Time.current.iso8601 })
    described_class.new(refresh: refresh, client: client).call
    expect(refresh.reload.state).to eq("failed")
    expect(client).to have_received(:accounts).once
  end

  it "quarantines same-time balance revisions and stages changed transaction versions" do
    allow(client).to receive(:accounts).and_return(payload)
    described_class.new(refresh: refresh, client: client).call
    payload["accounts"][0]["balance"] = "850.00"
    payload["accounts"][0]["transactions"][0]["description"] = "Corrected description"
    @refresh = nil
    described_class.new(refresh: refresh, client: client).call
    expect(mapping.provider_balances.where(state: "disputed").count).to eq(1)
    expect(mapping.latest_balance.balance).to eq(900)
    expect(mapping.provider_transactions.sole.previous_revisions.size).to eq(1)
  end
  it "rejects an in-flight response after the workspace restore generation changes" do
    run = refresh
    allow(client).to receive(:accounts) { workspace.increment!(:bank_sync_epoch); payload }
    described_class.new(refresh: run, client: client).call
    expect(run.reload.state).to eq("cancelled")
    expect(mapping.provider_balances).to be_empty
  end

  it "preserves other accounts when one account is malformed and renders provider errors safely" do
    payload["accounts"] << { "id" => "broken", "conn_id" => "institution-1", "name" => "Broken", "currency" => "USD", "balance" => "NaN", "balance-date" => 1.hour.ago.to_i }
    payload["errlist"] = [ { "code" => "con.auth", "conn_id" => "other-bank", "msg" => "<script>bad()</script> Reconnect https://secret:password@example.com" } ]
    allow(client).to receive(:accounts).and_return(payload)
    described_class.new(refresh: refresh, client: client).call
    expect(refresh.reload.state).to eq("partial")
    expect(mapping.provider_balances.count).to eq(1)
    expect(connection.reload.error_message).not_to include("<script>", "secret", "password")
  end
end
