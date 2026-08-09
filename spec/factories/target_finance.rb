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

  factory :data_transfer_run do
    association :budget_workspace
    operation { "restore" }
    payload_format_version { "2" }
    sequence(:payload_checksum) { |number| Digest::SHA256.hexdigest("transfer-#{number}") }
    state { "pending" }
  end

  factory :import_batch do
    association :budget_workspace
    import_kind { "account_activity" }
    sequence(:original_filename) { |number| "activity-#{number}.csv" }
    sequence(:file_digest) { |number| Digest::SHA256.hexdigest("import-#{number}") }
    sequence(:idempotency_key) { |number| "activity-import-#{number}" }
    parser_version { "1" }
    mapping_version { "1" }
    fingerprint_version { "1" }
    status { "previewed" }
  end

  factory :account_activity_import_draft do
    association :user
    budget_workspace { association :budget_workspace, legacy_owner_user: user }
    account do
      association :account,
        user: user,
        budget_workspace: budget_workspace,
        currency_code: budget_workspace.default_currency_code
    end
    sequence(:token_digest) { |number| Digest::SHA256.hexdigest("draft-token-#{number}") }
    sequence(:commit_idempotency_key) { |number| Digest::SHA256.hexdigest("activity-commit-#{number}") }
    file_digest { Digest::SHA256.hexdigest("activity-file") }
    rows_count { 0 }
    imported_count { 0 }
    duplicate_count { 0 }
    preview_payload do
      {
        "ok" => true,
        "account_id" => account.id,
        "file_digest" => file_digest,
        "commit_idempotency_key" => commit_idempotency_key,
        "rows_count" => rows_count,
        "imported_count" => imported_count,
        "duplicate_count" => duplicate_count,
        "original_filename" => "activity.csv",
        "header_row_number" => 1,
        "column_mapping" => {
          "transaction_on" => "Date",
          "description" => "Description",
          "raw_amount" => "Amount"
        },
        "amount_strategy" => "charges_are_negative",
        "warnings" => [],
        "rows" => []
      }
    end
    state { "previewed" }
    expires_at { 15.minutes.from_now }
  end
end
