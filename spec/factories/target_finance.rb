FactoryBot.define do
  factory :budget_workspace do
    sequence(:name) { |number| "Household #{number}" }
    default_currency_code { "USD" }
    status { "active" }
  end

  factory :workspace_membership do
    association :budget_workspace
    association :user
    role { "owner" }
    status { "active" }
    joined_at { Time.current }
  end

  factory :workspace_account, parent: :account do
    association :budget_workspace
    currency_code { budget_workspace.default_currency_code }
  end

  factory :category do
    association :budget_workspace
    sequence(:name) { |number| "Category #{number}" }
    flow_kind { "outflow" }
    budget_group { "variable" }
  end

  factory :budget_period do
    association :budget_workspace
    sequence(:starts_on) { |number| Date.new(2026, 1, 1).next_month(number - 1) }
    currency_code { budget_workspace.default_currency_code }
    state { "open" }
  end

  factory :planning_template do
    association :budget_workspace
    sequence(:name) { |number| "Template #{number}" }
    kind { "bill" }
    flow_kind { "outflow" }
    budget_group { "fixed" }
    default_amount { 100 }
    currency_code { budget_workspace.default_currency_code }
  end

  factory :budget_item do
    association :budget_workspace
    budget_period { association :budget_period, budget_workspace: budget_workspace }
    flow_kind { "outflow" }
    budget_group { "variable" }
    planned_amount { 100 }
    currency_code { budget_workspace.default_currency_code }
    state { "open" }
    origin_kind { "manual" }
  end

  factory :financial_transaction do
    association :budget_workspace
    effective_on { Date.new(2026, 8, 15) }
    description { "Target transaction" }
    gross_amount { 100 }
    currency_code { budget_workspace.default_currency_code }
    flow_kind { "outflow" }
    state { "posted" }
    origin_kind { "manual" }
  end

  factory :account_posting do
    association :budget_workspace
    financial_transaction { association :financial_transaction, budget_workspace: budget_workspace }
    account { association :workspace_account, budget_workspace: budget_workspace }
    amount { -100 }
    currency_code { budget_workspace.default_currency_code }
    role { "primary" }
    sequence_number { 0 }
  end

  factory :budget_allocation do
    association :budget_workspace
    budget_item { association :budget_item, budget_workspace: budget_workspace }
    financial_transaction { association :financial_transaction, budget_workspace: budget_workspace }
    amount { 100 }
    currency_code { budget_workspace.default_currency_code }
    match_kind { "manual" }
    matched_at { Time.current }
  end

  factory :balance_observation do
    association :budget_workspace
    account { association :workspace_account, budget_workspace: budget_workspace }
    observed_at { Time.current }
    effective_through_at { observed_at }
    balance { 1_000 }
    currency_code { budget_workspace.default_currency_code }
    source_kind { "manual" }
    status { "trusted" }
  end

  factory :operation_run do
    association :budget_workspace
    operation_type { "spec_operation" }
    sequence(:idempotency_key) { |number| "spec-operation-#{number}" }
    request_digest { Digest::SHA256.hexdigest(idempotency_key) }
    state { "pending" }
  end
end
