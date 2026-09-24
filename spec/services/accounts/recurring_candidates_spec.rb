require "rails_helper"

RSpec.describe "Recurring candidate decisions" do
  include RecurringCandidateHelpers
  let(:user) { create(:user) }
  let(:source) { recurring_candidate(user: user) }
  let(:account) { source.first }
  let(:candidate) { source.last }

  def resolve(**overrides)
    Accounts::RecurringCandidates::Resolve.call(**candidate_arguments(user: user, account: account, candidate: candidate, **overrides))
  end

  it "saves one template and decision on replay without creating actuals or month items" do
    2.times { resolve }
    decision = account.recurring_candidate_decisions.sole
    expect(decision).to be_status_linked
    expect(user.subscriptions.sole).to have_attributes(linked_account: account, amount: 12.to_d)
    expect(user.expense_entries).to be_empty
    expect(FinancialTransaction.count).to eq(0)
    expect(account.account_activities.count).to eq(3)
  end

  it "atomically synchronizes the template in an enabled workspace" do
    account
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.update!(target_writes_enabled: true, target_reads_enabled: true)
    account.reload
    decision = resolve
    expect(decision.budget_workspace).to eq(workspace)
    expect(workspace.planning_templates.sole).to have_attributes(source_account: account, name: candidate[:merchant])
    expect(workspace.planning_templates.sole.recurrence_rule.day_one).to eq(8)
  end

  it "rolls back the template and decision if target synchronization fails" do
    allow(Platform::TargetSync::PlanningTemplateWriter).to receive(:call).and_raise(Platform::TargetSync::WriteRejected, "Sync rejected")
    expect { resolve }.to raise_error(Accounts::RecurringCandidates::Resolve::Invalid, /Sync rejected/)
    expect(user.subscriptions).to be_empty
    expect(account.recurring_candidate_decisions).to be_empty
  end

  it "rejects invalid form values and forged linked accounts without a decision" do
    expect { resolve(attributes: { name: "", amount: -1, due_day: 32 }) }.to raise_error(Accounts::RecurringCandidates::Resolve::Invalid)
    other = create(:account)
    expect { resolve(attributes: { name: "Cloud", amount: 12, due_day: 8, linked_account_id: other.id }) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(account.recurring_candidate_decisions).to be_empty
  end

  it "detects changed evidence and rejects conflicting stale decisions" do
    args = candidate_arguments(user: user, account: account, candidate: candidate)
    account.account_activities.first.update!(amount: 13)
    expect { Accounts::RecurringCandidates::Resolve.call(**args) }.to raise_error(Accounts::RecurringCandidates::Resolve::Invalid, /activity changed/)
    fresh = Accounts::RecurringCandidates::Query.new(account: account).find!(candidate[:key])
    Accounts::RecurringCandidates::Resolve.call(**args.merge(evidence_digest: fresh[:evidence_digest]))
    expect { resolve(action: "ignore") }.to raise_error(Accounts::RecurringCandidates::Resolve::Invalid, /already reviewed/)
  end

  it "links an owned inactive bill without changing its settings" do
    bill = create(:monthly_bill, user: user, active: false, default_amount: 95, due_day: 20)
    decision = resolve(action: "link", template_token: "monthly_bill:#{bill.id}")
    expect(decision.template).to eq(bill)
    expect(bill.reload).to have_attributes(active: false, default_amount: 95.to_d, due_day: 20)
    expect(user.subscriptions).to be_empty
  end

  it "denies foreign templates, accounts, and viewer memberships" do
    other = create(:subscription)
    expect { resolve(action: "link", template_token: "subscription:#{other.id}") }.to raise_error(ActiveRecord::RecordNotFound)
    expect { resolve(user: create(:user)) }.to raise_error(ActiveRecord::RecordNotFound)
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.workspace_memberships.find_by!(user: user).update!(role: "viewer")
    account.reload
    expect { resolve }.to raise_error(Identity::WorkspaceAccess::NotAuthorized)
  end

  it "restores ignored decisions and reopens deleted template links" do
    resolve(action: "ignore")
    ignored = Accounts::RecurringCandidates::Query.new(account: account).find!(candidate[:key])
    Accounts::RecurringCandidates::Resolve.call(**candidate_arguments(user: user, account: account, candidate: ignored, action: "reopen"))
    restored = Accounts::RecurringCandidates::Query.new(account: account).find!(candidate[:key])
    decision = Accounts::RecurringCandidates::Resolve.call(**candidate_arguments(user: user, account: account, candidate: restored))
    decision.template.destroy!
    expect(decision.reload).to have_attributes(status: "unreviewed", subscription_id: nil)
  end

  it "retains decisions after evidence disappears and across later imports" do
    resolve(action: "ignore")
    account.account_activities.delete_all
    result = Accounts::RecurringCandidates::Query.new(account: account).find!(candidate[:key])
    expect(result).to include(review_status: "ignored", evidence_available: false, merchant: "Cloud storage")
    recurring_candidate(user: user, account: account, amount: 15)
    expect(Accounts::RecurringCandidates::Query.new(account: account).find!(candidate[:key])).to include(review_status: "ignored", evidence_available: true)
  end

  it "uses a case-insensitive identity independent of amount and excludes fees and transfers" do
    expect(Accounts::RecurringCandidates::Detector.key("  CLOUD storage ")).to eq(candidate[:key])
    [ "Monthly service fee", "Purchase interest", "Card payment", "Savings transfer" ].each do |name|
      import = create(:account_activity_import, account: account, user: user)
      (7..9).each { |month| create(:account_activity, account: account, user: user, account_activity_import: import, description: name, transaction_on: Date.new(2026, month, 8), amount: 12, account_delta: -12) }
    end
    expect(Accounts::RecurringCandidates::Detector.new(account: account).call.map { |item| item[:merchant] }).to eq([ "Cloud storage" ])
  end

  it "applies review state before the twelve-row insights limit" do
    account
    13.times { |n| recurring_candidate(user: user, account: account, name: "Software #{n}") }
    resolve(action: "ignore")
    rows = Accounts::ActivityInsights::Report.new(account: account).call[:active_subscription_candidates]
    expect(rows.size).to eq(12)
    expect(rows.map { |item| item[:key] }).not_to include(candidate[:key])
  end

  it "drills down to all supporting charges across merchant capitalization" do
    candidate
    account.account_activities.first.update!(description: "CLOUD STORAGE")
    rows = Accounts::ActivityLedgerQuery.new(account: account, filters: {
      source: "institution_activity", recurring_candidate: candidate[:key], merchant: "Cloud storage"
    }).call.fetch(:institution_rows)
    expect(rows.size).to eq(3)
  end
end
