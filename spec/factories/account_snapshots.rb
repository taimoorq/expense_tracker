FactoryBot.define do
  factory :account_snapshot do
    association :account
    recorded_on { Date.current }
    balance { 1250.50 }
    available_balance { nil }
    notes { nil }
  end
end
