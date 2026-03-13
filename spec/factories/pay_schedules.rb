FactoryBot.define do
  factory :pay_schedule do
    association :user
    sequence(:name) { |n| "Employer #{n}" }
    cadence { :monthly }
    amount { 2500 }
    first_pay_on { Date.new(2026, 3, 1) }
    day_of_month_one { 15 }
    weekend_adjustment { :no_adjustment }
    account { "Checking" }
    active { true }
  end
end
