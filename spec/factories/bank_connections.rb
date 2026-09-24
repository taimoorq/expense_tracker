FactoryBot.define do
  factory :bank_connection do
    association :budget_workspace
    actor_membership { association :workspace_membership, budget_workspace: budget_workspace }
    sequence(:claim_fingerprint) { |n| Digest::SHA256.hexdigest("bank-#{n}") }
    status { "active" }
    access_url { "https://demo:private-test-token@beta-bridge.simplefin.org/simplefin" }
  end

  factory :connected_account do
    association :bank_connection
    budget_workspace { bank_connection.budget_workspace }
    account { association :workspace_account, budget_workspace: budget_workspace, user: bank_connection.actor_membership.user }
    provider_connection_id { "institution-1" }
    sequence(:provider_account_id) { |n| "account-#{n}" }
    name { "Bank checking" }
    institution_name { "Demo bank" }
    currency { "USD" }
    state { "mapped" }
  end

  factory :provider_balance do
    association :connected_account
    budget_workspace { connected_account.budget_workspace }
    balance { 2850 }
    currency { "USD" }
    reported_at { Time.current.change(usec: 0) }
    fetched_at { Time.current }
    sequence(:content_digest) { |n| Digest::SHA256.hexdigest("balance-#{n}") }
  end

  factory :provider_transaction do
    association :connected_account
    budget_workspace { connected_account.budget_workspace }
    sequence(:provider_id) { |n| "transaction-#{n}" }
    sequence(:content_digest) { |n| Digest::SHA256.hexdigest("transaction-#{n}") }
    currency { "USD" }
    description { "Bank payment" }
    amount { -350 }
    posted_at { Time.current.change(usec: 0) }
    fetched_at { Time.current }
  end
end
