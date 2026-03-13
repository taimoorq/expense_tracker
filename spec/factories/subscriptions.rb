FactoryBot.define do
  factory :subscription do
    association :user
    sequence(:name) { |n| "Subscription #{n}" }
    amount { 19.99 }
    due_day { 8 }
    account { "Visa" }
    notes { "Recurring service" }
    active { true }
  end
end
