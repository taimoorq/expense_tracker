require "faker"

FactoryBot.define do
  factory :account_activity do
    association :account_activity_import
    account { account_activity_import.account }
    user { account.user }
    transaction_on { Date.new(2026, 1, 1) }
    posted_on { Date.new(2026, 1, 2) }
    sequence(:description) { |n| "#{Faker::Commerce.vendor} #{n}" }
    category { Faker::Commerce.department(max: 1) }
    activity_type { %w[Sale Payment Interest Fee Transfer].sample }
    raw_amount { -42.50 }
    amount { 42.50 }
    account_delta { -42.50 }
    row_number { 2 }
    sequence(:fingerprint) { |n| "#{Faker::Internet.uuid}-#{n}" }
    raw_payload { { "Description" => description } }
  end
end
