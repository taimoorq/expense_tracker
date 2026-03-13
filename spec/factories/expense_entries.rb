FactoryBot.define do
  factory :expense_entry do
    association :budget_month
    user { budget_month.user }
    occurred_on { budget_month.month_on }
    section { :fixed }
    category { "Utilities" }
    payee { "Power Co" }
    planned_amount { 125.50 }
    actual_amount { nil }
    account { "Checking" }
    status { :planned }
    need_or_want { "Need" }
    notes { "Monthly bill" }
    source_file { "manual" }
  end
end
