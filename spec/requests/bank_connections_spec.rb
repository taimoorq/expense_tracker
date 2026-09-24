require "rails_helper"

RSpec.describe "Bank connections", type: :request do
  let(:user) { create(:user) }
  let(:context) { Identity::PersonalWorkspaceProvisioner.call(user: user) }
  let(:connection) { create(:bank_connection, budget_workspace: context.workspace, actor_membership: context.membership) }
  before { sign_in user }

  it "keeps credentials out of connection pages and rejects foreign connection IDs" do
    get bank_connection_path(connection)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Reconnect with a fresh token", "bank_connection_status")
    expect(Nokogiri::HTML(response.body).at_css("turbo-frame#bank_connection_status").text).to include("Connection settings")
    get bank_connection_path(connection), headers: { "Turbo-Frame" => "bank_connection_status" }
    expect(Nokogiri::HTML(response.body).at_css("turbo-frame#bank_connection_status").text).to include("Connection settings")
    expect(response.body).not_to include("private-test-token", connection.encrypted_access_url)
    get bank_connection_path(create(:bank_connection))
    expect(response).to have_http_status(:not_found)
  end

  it "claims a token once, queues only record IDs, and disconnects without deleting history" do
    client = instance_double(BankConnections::Simplefin::Client, claim: "https://u:secret@bridge.simplefin.org/simplefin")
    allow(BankConnections::Simplefin::Client).to receive(:new).and_return(client)
    2.times { post bank_connections_path, params: { setup_token: "opaque-token" } }
    expect(client).to have_received(:claim).once
    saved = context.workspace.bank_connections.sole
    expect(saved.bank_refreshes.count).to eq(1)
    expect(saved.bank_refreshes.sole.operation_run.job_arguments).to eq([])
    mapping = create(:connected_account, bank_connection: saved)
    create(:provider_balance, connected_account: mapping)
    delete bank_connection_path(saved)
    expect(saved.reload).to have_attributes(status: "disconnected", encrypted_access_url: nil)
    expect(mapping.provider_balances.count).to eq(1)
    expect(saved.bank_refreshes.sole.state).to eq("cancelled")
  end

  it "does not map an account belonging to another user" do
    mapping = create(:connected_account, bank_connection: connection, account: nil, state: "discovered")
    foreign = create(:account)
    patch map_account_bank_connection_path(connection), params: { mapping_id: mapping.id, account_id: foreign.id }
    expect(response).to have_http_status(:not_found)
    expect(mapping.reload.account_id).to be_nil
  end

  it "renders mapping and reconciliation forms for a saved balance" do
    mapping = create(:connected_account, bank_connection: connection)
    create(:provider_balance, connected_account: mapping)
    get bank_connection_path(connection)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Bank reported", "Not provided", "Save mapping")
    get reconcile_connected_account_path(mapping)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Use this bank balance", "No outstanding recorded payments")

    manual = create(:account, user: user, name: "Cash envelope", kind: :cash)
    get accounts_path
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    [ "account_#{mapping.account_id}", "mobile_account_#{mapping.account_id}" ].each do |id|
      row = document.at_css("#tracked_accounts ##{id}")
      expect(row.text).to include("SimpleFIN", "$2,850.00", "Review balance", "Manage connection")
      expect(row.css("details.ta-row-actions a").map(&:text)).to include("Import activity", "Edit account", "Manage connection")
      expect(row.at_css("a[href='#{reconcile_connected_account_path(mapping)}']")).to be_present
      expect(row.at_css("a[href='#{bank_connection_path(connection, anchor: "connected_account_#{mapping.id}")}']")).to be_present
    end
    expect(document.at_css("#account_#{manual.id}").text).not_to include("SimpleFIN", "$2,850.00")
    expect(document.css("section[aria-label^='Bank balance for']")).to be_empty
  end
end
