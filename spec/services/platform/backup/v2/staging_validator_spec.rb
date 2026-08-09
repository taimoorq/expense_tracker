require "rails_helper"

RSpec.describe Platform::Backup::V2::StagingValidator do
  let(:scopes) { Platform::Backup::V2::Preview::FINANCIAL_SCOPES }

  it "rejects a missing relationship after checksum validation and before destination creation" do
    source = create(:user)
    account = create(:account, user: source)
    month = create(:budget_month, user: source)
    create(:expense_entry, user: source, budget_month: month, source_account: account, status: :paid, actual_amount: 25)
    Platform::TargetBackfill::Runner.call(user: source)
    payload = Platform::Backup::V2::Exporter.new(user: source, scopes: scopes).as_json.deep_dup
    payload.dig(:data, :account_activity, :account_postings).first[:account_external_id] = SecureRandom.uuid
    unsigned = payload.except(:payload_checksum)
    payload[:payload_checksum] = Digest::SHA256.hexdigest(Platform::CanonicalJson.dump(unsigned))

    result = described_class.new(payload: payload, scopes: scopes).call

    expect(result).to eq(success: false, error: "The backup references a missing account.")
  end

  it "returns a normalized record-count manifest for a valid stage" do
    source = create(:user)
    create(:account, user: source)
    Platform::TargetBackfill::Runner.call(user: source)
    payload = Platform::Backup::V2::Exporter.new(user: source, scopes: scopes).as_json

    result = described_class.new(payload: payload, scopes: scopes).call

    expect(result).to include(success: true)
    expect(result.fetch(:manifest)).to include("account" => 1, "transaction" => 0)
  end
end
