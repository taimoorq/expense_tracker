require "rails_helper"

RSpec.describe Accounts::SnapshotWriter do
  def prepare_target(user)
    result = Platform::TargetBackfill::Runner.call(user: user)
    expect(result).to be_success
    result.workspace.update!(target_writes_enabled: true)
    result.workspace
  end

  it "records a new balance as trusted target evidence" do
    user = create(:user)
    account = create(:account, user: user)
    workspace = prepare_target(user)

    snapshot = described_class.create(
      account: account,
      attributes: { recorded_on: Date.new(2026, 8, 4), balance: 1_250, available_balance: 1_200 }
    )

    expect(snapshot).to be_persisted
    mapping = workspace.legacy_record_mappings.find_by!(
      legacy_record_type: "AccountSnapshot",
      legacy_record_id: snapshot.id,
      target_record_type: "BalanceObservation"
    )
    observation = BalanceObservation.find(mapping.target_record_id)
    expect(observation).to have_attributes(
      account: account,
      balance: 1_250.to_d,
      available_balance: 1_200.to_d,
      source_kind: "manual",
      status: "trusted"
    )
  end

  it "supersedes prior evidence instead of rewriting history when a snapshot changes" do
    user = create(:user)
    account = create(:account, user: user)
    snapshot = create(:account_snapshot, account: account, recorded_on: Date.new(2026, 8, 4), balance: 1_250)
    workspace = prepare_target(user)
    prior = workspace.balance_observations.sole

    updated = described_class.update(snapshot: snapshot, attributes: { balance: 1_400, notes: "Corrected" })

    expect(updated).to be(true)
    expect(prior.reload).to be_status_superseded
    current = workspace.balance_observations.status_trusted.sole
    expect(current).to have_attributes(balance: 1_400.to_d, notes: "Corrected")
    mapping = workspace.legacy_record_mappings.find_by!(
      legacy_record_type: "AccountSnapshot",
      legacy_record_id: snapshot.id,
      target_record_type: "BalanceObservation"
    )
    expect(mapping.target_record_id).to eq(current.id)
    expect(mapping.metadata.fetch("prior_target_ids")).to include(prior.id)
  end

  it "supersedes target evidence before deleting the legacy snapshot" do
    user = create(:user)
    account = create(:account, user: user)
    snapshot = create(:account_snapshot, account: account)
    workspace = prepare_target(user)

    destroyed = described_class.destroy(snapshot: snapshot)

    expect(destroyed).to be(true)
    expect(AccountSnapshot.find_by(id: snapshot.id)).to be_nil
    expect(workspace.balance_observations.sole).to be_status_superseded
    expect(
      workspace.legacy_record_mappings.find_by!(
        legacy_record_type: "AccountSnapshot",
        legacy_record_id: snapshot.id,
        target_record_type: "BalanceObservation"
      )
    ).to be_status_omitted
  end
end
