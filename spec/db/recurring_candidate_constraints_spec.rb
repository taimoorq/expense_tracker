require "rails_helper"

RSpec.describe "Recurring candidate database constraints" do
  include RecurringCandidateHelpers

  it "rejects duplicate identities and a linked decision without a template even if validation is bypassed" do
    user = create(:user)
    account, candidate = recurring_candidate(user: user)
    decision = Accounts::RecurringCandidates::Resolve.call(**candidate_arguments(user: user, account: account, candidate: candidate, action: "ignore"))
    expect do
      AccountRecurringCandidateDecision.transaction(requires_new: true) do
        AccountRecurringCandidateDecision.insert_all!([ decision.attributes.except("id") ])
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
    expect do
      AccountRecurringCandidateDecision.transaction(requires_new: true) { decision.update_columns(status: "linked") }
    end.to raise_error(ActiveRecord::StatementInvalid, /recurring_candidate_resolution/)
  end
end
