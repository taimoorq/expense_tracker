FactoryBot.define do
  factory :account do
    association :user
    sequence(:name) { |n| "Account #{n}" }
    institution_name { "Ally" }
    kind { :savings }
    active { true }
    include_in_net_worth { true }
    include_in_cash { false }
  end
end
