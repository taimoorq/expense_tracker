class TellerAccountSnapshotSync
  Result = Struct.new(:success?, :snapshot, :error, keyword_init: true)

  def initialize(account:, client: nil, recorded_on: Date.current)
    @account = account
    @client = client
    @recorded_on = recorded_on
  end

  def call
    return Result.new(success?: false, error: "Teller is not enabled for this app.") unless TellerConfiguration.enabled?
    return Result.new(success?: false, error: "This account is not connected to Teller.") unless account.teller_connected?

    balances = client.fetch_balances(account_id: account.teller_account_id)

    snapshot = account.account_snapshots.find_or_initialize_by(recorded_on: recorded_on)
    snapshot.balance = balances.fetch("ledger").presence || balances.fetch("available")
    snapshot.available_balance = balances["available"]
    snapshot.notes = [snapshot.notes.presence, "Synced from Teller"].compact.uniq.join(" - ")
    snapshot.save!

    account.update!(teller_last_synced_at: Time.current)

    Result.new(success?: true, snapshot: snapshot)
  rescue TellerClient::Error, KeyError, ActiveRecord::RecordInvalid => error
    Result.new(success?: false, error: error.message)
  end

  private

  attr_reader :account, :recorded_on

  def client
    @client ||= TellerClient.new(access_token: account.teller_access_token)
  end
end
