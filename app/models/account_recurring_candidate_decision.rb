class AccountRecurringCandidateDecision < ApplicationRecord
  belongs_to :user
  belongs_to :account
  belongs_to :budget_workspace, optional: true
  belongs_to :subscription, optional: true
  belongs_to :monthly_bill, optional: true

  enum :status, { unreviewed: "unreviewed", linked: "linked", ignored: "ignored" }, prefix: true

  validates :merchant_key, format: { with: /\A[0-9a-f]{64}\z/ }, uniqueness: { scope: [ :account_id, :key_version ] }
  validates :key_version, inclusion: { in: [ 1 ] }
  validate :consistent_ownership
  validate :consistent_resolution
  validate :valid_evidence_summary

  def template
    return subscription if subscription_id.present?
    monthly_bill if monthly_bill_id.present?
  end

  private

  def consistent_ownership
    errors.add(:account, "must belong to the same user and workspace") unless account&.user_id == user_id && account&.budget_workspace_id == budget_workspace_id
    linked = []
    linked << subscription if subscription_id.present?
    linked << monthly_bill if monthly_bill_id.present?
    linked.each do |record|
      unless record.user_id == user_id && record.budget_workspace_id == budget_workspace_id
        errors.add(:base, "The recurring transaction must belong to the same user and workspace")
      end
    end
  end

  def consistent_resolution
    count = [ subscription_id, monthly_bill_id ].compact.size
    errors.add(:status, "does not match the recurring transaction link") unless status_linked? ? count == 1 : count.zero?
  end

  def valid_evidence_summary
    summary = evidence_summary
    valid = summary.is_a?(Hash) && summary["merchant"].is_a?(String) && summary["merchant"].present? &&
      summary["count"].is_a?(Integer) && summary["count"] >= 2 &&
      summary["months_seen"].is_a?(Integer) && summary["months_seen"] >= 2 &&
      summary["estimated_amount"].to_s.match?(/\A\d+(\.\d+)?\z/)
    if valid
      %w[first_on last_on history_through].each { |key| Date.iso8601(summary.fetch(key)) }
    else
      errors.add(:evidence_summary, "must contain the reviewed charge summary")
    end
  rescue ArgumentError, KeyError, TypeError
    errors.add(:evidence_summary, "contains invalid evidence dates")
  end
end
