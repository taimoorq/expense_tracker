module RecurringCandidateHelpers
  def recurring_candidate(user:, account: nil, name: "Cloud storage", amount: 12)
    account ||= create(:account, user: user, name: "Candidate checking")
    import = create(:account_activity_import, account: account, user: user)
    (7..9).each do |month|
      create(:account_activity, account: account, user: user, account_activity_import: import,
        description: name, category: "Software", activity_type: "Sale", row_number: month, transaction_on: Date.new(2026, month, 8),
        posted_on: Date.new(2026, month, 8), amount: amount, raw_amount: -amount, account_delta: -amount)
    end
    key = Accounts::RecurringCandidates::Detector.key(name)
    [ account, Accounts::RecurringCandidates::Query.new(account: account).find!(key) ]
  end

  def candidate_arguments(user:, account:, candidate:, action: "create", **overrides)
    {
      user: user, account: account, key: candidate[:key], action: action,
      expected_version: candidate[:decision]&.lock_version || -1, evidence_digest: candidate[:evidence_digest],
      attributes: { name: candidate[:merchant], amount: "12.00", due_day: 8, linked_account_id: account.id }
    }.merge(overrides)
  end
end
