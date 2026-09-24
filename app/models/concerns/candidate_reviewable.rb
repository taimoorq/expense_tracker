module CandidateReviewable
  extend ActiveSupport::Concern

  included do
    has_many :recurring_candidate_decisions, class_name: "AccountRecurringCandidateDecision"
    before_destroy :reopen_recurring_candidates
  end

  private

  def reopen_recurring_candidates
    recurring_candidate_decisions.update_all(
      status: "unreviewed", subscription_id: nil, monthly_bill_id: nil,
      request_digest: nil, reviewed_at: nil, updated_at: Time.current
    )
  end
end
