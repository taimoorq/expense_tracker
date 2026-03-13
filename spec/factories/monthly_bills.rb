FactoryBot.define do
  factory :monthly_bill do
    association :user
    sequence(:name) { |n| "Monthly Bill #{n}" }
    kind { :fixed_payment }
    default_amount { 210.75 }
    due_day { 12 }
    account { "Checking" }
    notes { "Expected monthly bill" }
    active { true }
  end
end
