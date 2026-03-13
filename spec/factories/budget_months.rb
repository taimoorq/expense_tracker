FactoryBot.define do
  factory :budget_month do
    association :user
    sequence(:month_on) { |n| Date.new(2026, ((n - 1) % 12) + 1, 1) }
    sequence(:label) { |n| Date.new(2026, ((n - 1) % 12) + 1, 1).strftime("%B %Y") }
  end
end