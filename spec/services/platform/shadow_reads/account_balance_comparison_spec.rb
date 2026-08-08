require "rails_helper"

RSpec.describe Platform::ShadowReads::AccountBalanceComparison do
  it "reports exact parity without persisting financial values" do
    user = create(:user)
    account = create(:account, user: user)
    create(:account_snapshot, account: account, recorded_on: Date.new(2026, 7, 1), balance: 1_000)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace

    result = described_class.call(account: account.reload, as_of: Date.new(2026, 7, 5))

    expect(result).to be_matched
    expect(result.mismatched_fields).to be_empty
    expect(workspace.migration_discrepancies.where(code: "shadow_account_balance_mismatch")).to be_empty
  end

  it "persists only the account, boundary, and mismatched field names" do
    user = create(:user)
    account = create(:account, user: user)
    create(:account_snapshot, account: account, recorded_on: Date.new(2026, 7, 1), balance: 1_000)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.balance_observations.sole.update!(balance: 999)

    result = described_class.call(account: account.reload, as_of: Date.new(2026, 7, 5))

    expect(result).not_to be_matched
    discrepancy = workspace.migration_discrepancies.find_by!(code: "shadow_account_balance_mismatch")
    expect(discrepancy).to be_status_open
    expect(discrepancy.redacted_details.keys).to contain_exactly("as_of", "mismatched_fields")
    expect(discrepancy.redacted_details.fetch("mismatched_fields")).to include("base_balance", "current_balance")
    expect(discrepancy.redacted_details.to_json).not_to include("999", "1000")
  end

  it "uses target balances only after the reversible read flag is enabled" do
    user = create(:user)
    account = create(:account, user: user)
    create(:account_snapshot, account: account, recorded_on: Date.new(2026, 7, 1), balance: 1_000)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.update!(target_writes_enabled: true, target_reads_enabled: true)

    expect(Accounts::TargetBalanceResolver).to receive(:new).and_call_original

    expect(account.reload.resolved_balance(as_of: Date.new(2026, 7, 5)).current_balance).to eq(1_000.to_d)
  end
end
