FactoryBot.define do
  factory :credit_card do
    association :user
    sequence(:name) { |n| "Card #{n}" }
    minimum_payment { 35 }
    due_day { 15 }
    priority { 1 }
    account { "Mastercard" }
    notes { "Snowball target" }
    active { true }
  end
end
