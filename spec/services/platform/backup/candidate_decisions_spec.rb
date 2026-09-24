require "rails_helper"

RSpec.describe Platform::Backup::CandidateDecisions do
  include RecurringCandidateHelpers
  let(:user) { create(:user) }
  let(:source) { recurring_candidate(user: user) }
  let(:account) { source.first }
  let(:candidate) { source.last }

  def resolve
    Accounts::RecurringCandidates::Resolve.call(**candidate_arguments(user: user, account: account, candidate: candidate))
  end

  it "round-trips V1 links to duplicate-named templates by portable position, not name or database ID" do
    decision = resolve
    create(:subscription, user: user, name: decision.template.name, amount: 80, due_day: 8)
    ignored_account, ignored = recurring_candidate(user: user, account: account, name: "Music subscription")
    Accounts::RecurringCandidates::Resolve.call(**candidate_arguments(user: user, account: ignored_account, candidate: ignored, action: "ignore"))
    scopes = %w[accounts planning_templates account_activity]
    payload = Platform::UserDataExport.new(user: user, scopes: scopes).as_json
    restored = create(:user)
    result = Platform::UserDataImport.new(user: restored, payload: payload, scopes: scopes).call
    expect(result).to include(success: true)
    link = restored.recurring_candidate_decisions.status_linked.sole
    expect(link.template.amount).to eq(12.to_d)
    expect(link.template.id).not_to eq(decision.template.id)
    expect(restored.recurring_candidate_decisions.status_ignored.count).to eq(1)
    expect(link.account.user).to eq(restored)
  end

  it "carries pre-migration decisions into the workspace and round-trips V2 after legacy projection" do
    decision = resolve
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    expect(decision.reload.budget_workspace).to eq(workspace)
    scopes = Platform::Backup::V2::Preview::FINANCIAL_SCOPES
    payload = Platform::Backup::V2::Exporter.new(user: user, scopes: scopes).as_json
    validation = Platform::Backup::V2::StagingValidator.new(payload: payload, scopes: scopes).call
    expect(validation).to include(success: true)
    restored = create(:user)
    result = Platform::UserDataImport.new(user: restored, payload: payload, scopes: scopes).call
    expect(result).to include(success: true)
    link = restored.recurring_candidate_decisions.sole
    expect(link).to have_attributes(status: "linked", merchant_key: candidate[:key])
    expect(link.template).to eq(restored.subscriptions.sole)
    expect(link.template.id).not_to eq(decision.template.id)
    expect(link.account).to eq(restored.accounts.sole)
  end

  it "rejects a V1 invalid index transactionally instead of guessing a template" do
    resolve
    scopes = %w[accounts planning_templates]
    payload = Platform::UserDataExport.new(user: user, scopes: scopes).as_json
    payload[:data][:recurring_candidate_decisions].first["template_index"] = -1
    restored = create(:user)
    result = Platform::UserDataImport.new(user: restored, payload: payload, scopes: scopes).call
    expect(result).to include(success: false)
    expect(restored.accounts.reload).to be_empty
    expect(restored.subscriptions.reload).to be_empty
  end

  it "keeps older backups valid and excludes incomplete decision references from partial exports" do
    resolve
    partial = Platform::UserDataExport.new(user: user, scopes: %w[accounts]).as_json
    expect(partial[:data]).not_to have_key(:recurring_candidate_decisions)
    scopes = %w[accounts planning_templates]
    payload = Platform::UserDataExport.new(user: user, scopes: scopes).as_json
    payload[:data].delete(:recurring_candidate_decisions)
    restored = create(:user)
    expect(Platform::UserDataImport.new(user: restored, payload: payload, scopes: scopes).call).to include(success: true)
    expect(restored.recurring_candidate_decisions).to be_empty
  end

  it "does not silently erase decisions during an incomplete V1 replacement restore" do
    decision = resolve
    payload = Platform::UserDataExport.new(user: user, scopes: %w[accounts]).as_json
    result = Platform::UserDataImport.new(user: user, payload: payload, scopes: %w[accounts]).call
    expect(result).to include(success: false, error: /together/)
    expect(decision.reload).to be_status_linked
    expect(account.reload).to be_persisted
  end

  it "restores candidate decisions after replacing and rolling back a V2 workspace" do
    decision = resolve
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.update!(target_reads_enabled: true, target_writes_enabled: true)
    other = create(:user)
    create(:account, user: other, name: "Replacement account")
    Platform::TargetBackfill::Runner.call(user: other)
    scopes = Platform::Backup::V2::Preview::FINANCIAL_SCOPES
    payload = Platform::Backup::V2::Exporter.new(user: other, scopes: scopes).as_json
    result = Platform::UserDataImport.new(user: user, payload: payload, scopes: scopes, replace_existing: true).call
    expect(result).to include(success: true)
    expect(user.recurring_candidate_decisions.reload).to be_empty
    checkpoint = workspace.restore_checkpoints.find(result.fetch(:checkpoint_id))
    rollback = Platform::Backup::RestoreCheckpointRollback.call(user: user, checkpoint: checkpoint)
    expect(rollback).to include(success: true)
    restored = user.recurring_candidate_decisions.reload.sole
    expect(restored).to have_attributes(merchant_key: decision.merchant_key, status: "linked")
    expect(restored.template.name).to eq("Cloud storage")
  end
end
