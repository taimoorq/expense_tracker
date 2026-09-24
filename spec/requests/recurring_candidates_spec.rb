require "rails_helper"

RSpec.describe "Account recurring candidates", type: :request do
  include RecurringCandidateHelpers
  let(:user) { create(:user) }
  let(:source) { recurring_candidate(user: user) }
  let(:account) { source.first }
  let(:candidate) { source.last }
  before { sign_in user }

  def save_candidate(**overrides)
    patch account_recurring_candidate_path(account, candidate[:key]), params: {
      decision_action: "create", expected_version: -1, evidence_digest: candidate[:evidence_digest],
      candidate_template: { name: "Cloud storage", amount: "12.00", due_day: 8, linked_account_id: account.id }
    }.merge(overrides)
  end

  it "renders account actions and a bounded review page with a matching Turbo frame" do
    get account_path(account, view: "insights")
    expect(response.body).to include("Review recurring candidates", "Set up recurring")
    get account_recurring_candidates_path(account)
    expect(response.body).to include("Needs review (1)", "Cloud storage")
    get account_recurring_candidate_path(account, candidate[:key]), headers: { "Turbo-Frame" => "recurring_review" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="recurring_review"', "Expected amount", "Supporting charges")
  end

  it "saves and then optionally adds a planned item through the real routes" do
    month = create(:budget_month, user: user, month_on: Date.new(2026, 9, 1))
    save_candidate
    expect(response).to have_http_status(:see_other)
    expect(user.expense_entries).to be_empty
    follow_redirect!
    expect(response.body).to include("Linked to Cloud storage", "Add to month")
    get month_account_recurring_candidate_path(account, candidate[:key], budget_month_id: month.id)
    expect(response).to have_http_status(:ok)
    digest = Nokogiri::HTML(response.body).at_css('input[name="preview_digest"]')["value"]
    2.times do
      post add_to_month_account_recurring_candidate_path(account, candidate[:key]), params: { budget_month_id: month.id, preview_digest: digest }
      expect(response).to have_http_status(:see_other)
    end
    expect(month.expense_entries.sole).to have_attributes(status: "planned", source_account: account)
    follow_redirect!
    expect(response.body).to include("Already in this month")
  end

  it "preserves submitted values on errors and handles Turbo requests without section-replacement assumptions" do
    save_candidate(candidate_template: { name: "Edited name", amount: "-5", due_day: 8, linked_account_id: account.id })
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Edited name", "greater than 0")
    expect(user.subscriptions).to be_empty
    patch account_recurring_candidate_path(account, candidate[:key]), params: { decision_action: "ignore", expected_version: -1, evidence_digest: candidate[:evidence_digest] }, headers: { "Accept" => "text/vnd.turbo-stream.html", "Turbo-Frame" => "recurring_review" }
    expect(response).to have_http_status(:see_other)
    get account_recurring_candidates_path(account, status: "ignored")
    expect(response.body).to include("Ignored (1)", "Cloud storage")
  end

  it "does not expose or mutate another user's account, template, or month" do
    foreign = create(:account)
    get account_recurring_candidates_path(foreign)
    expect(response).to have_http_status(:not_found)
    sign_in user
    save_candidate(decision_action: "link", template_token: "subscription:#{create(:subscription).id}")
    expect(response).to have_http_status(:not_found)
    sign_in user
    save_candidate
    post add_to_month_account_recurring_candidate_path(account, candidate[:key]), params: { budget_month_id: create(:budget_month).id, preview_digest: "forged" }
    expect(response).to have_http_status(:not_found)
  end

  it "keeps the saved template if a month becomes closed after preview" do
    account
    month = create(:budget_month, user: user, month_on: Date.new(2026, 9, 1))
    workspace = Platform::TargetBackfill::Runner.call(user: user).workspace
    workspace.update!(target_reads_enabled: true, target_writes_enabled: true)
    account.reload
    save_candidate
    get month_account_recurring_candidate_path(account, candidate[:key], budget_month_id: month.id)
    digest = Nokogiri::HTML(response.body).at_css('input[name="preview_digest"]')["value"]
    workspace.budget_periods.sole.update!(state: "closed")
    post add_to_month_account_recurring_candidate_path(account, candidate[:key]), params: { budget_month_id: month.id, preview_digest: digest }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("recurring transaction is saved", "Reopen")
    expect(user.subscriptions.count).to eq(1)
    expect(month.expense_entries).to be_empty
  end
end
