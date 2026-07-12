require "faker"

FactoryBot.define do
  factory :account_activity_import do
    association :account
    user { account.user }
    original_filename { "#{Faker::Bank.name.parameterize}-activity.csv" }
    header_row_number { 1 }
    column_mapping do
      {
        transaction_on: "Transaction Date",
        description: "Description",
        raw_amount: "Amount"
      }
    end
    amount_strategy { "charges_are_negative" }
    rows_count { 1 }
    imported_count { 1 }
    duplicate_count { 0 }
    warning_messages { [] }
    started_on { Date.new(2026, 1, 1) }
    ended_on { Date.new(2026, 1, 1) }
  end
end
