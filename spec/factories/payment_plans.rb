FactoryBot.define do
  factory :payment_plan do
    association :user
    sequence(:name) { |n| "Plan #{n}" }
    total_due { 1200 }
    amount_paid { 200 }
    monthly_target { 150 }
    due_day { 20 }
    account { "Checking" }
    notes { "Installment plan" }
    active { true }
  end
end