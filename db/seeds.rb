seed_source = "seed:generated_history"
seed_buffer_source = "seed:cashflow_buffer"
target_leftover = BigDecimal("1200")
seed_mode = ENV.fetch("SEED_MODE", "users").to_s.strip.presence || "users"
valid_seed_modes = %w[users users_with_transactions]
seed_email = ENV.fetch("SEED_USER_EMAIL", "demo@example.com")
seed_password = ENV.fetch("SEED_USER_PASSWORD", "password123!")
admin_seed_email = ENV["ADMIN_USER_EMAIL"].to_s.strip
seeded_history_months = (1..6).map { |offset| Date.current.beginning_of_month.prev_month(offset) }.sort

unless valid_seed_modes.include?(seed_mode)
  raise ArgumentError, "Invalid SEED_MODE=#{seed_mode.inspect}. Expected one of: #{valid_seed_modes.join(', ')}"
end

seed_transactions = seed_mode == "users_with_transactions"

puts "Seeding Expense Tracker demo data..."
puts "- Seed mode: #{seed_mode}"
puts "- Demo user email: #{seed_email}"
puts "- Admin user email: #{admin_seed_email}" if admin_seed_email.present?
puts "- Seed history months: #{seeded_history_months.map { |month| month.strftime('%B %Y') }.join(', ')}" if seed_transactions

admin_bootstrap_result = AdminBootstrapper.new.call
puts "- Admin user #{admin_bootstrap_result.status}: #{admin_bootstrap_result.admin_user.email}" if admin_bootstrap_result.admin_user

seeded_template_names = {
  pay_schedules: [ "Main Paycheck", "Side Hustle Paycheck" ],
  subscriptions: [ "Netflix", "Google One", "Apple iCloud", "Streaming Service", "Cloud Storage", "Device Backup" ],
  monthly_bills: [ "Housing Payment", "Electric", "Car Insurance", "Property Taxes" ],
  payment_plans: [ "Installment Plan", "Student Loan" ],
  credit_cards: [ "Visa Everyday", "Chase Freedom", "Everyday Visa", "Rewards Mastercard" ]
}

seeded_account_names = [
  "Everyday Checking",
  "Emergency Savings",
  "Long-Term Brokerage",
  "401(k) Portfolio",
  "Wallet Cash",
  "Car Value",
  "Rewards Visa Balance",
  "Student Loan Balance",
  "Home Repair Reserve"
]

seed_user = User.find_or_initialize_by(email: seed_email)
user_status = seed_user.new_record? ? "created" : "updated"

if seed_user.new_record? || !seed_user.valid_password?(seed_password)
  seed_user.password = seed_password
  seed_user.password_confirmation = seed_password
  seed_user.save!
end

puts "- Demo user #{user_status}: #{seed_user.email}"

seed_user.pay_schedules.where(name: seeded_template_names[:pay_schedules]).delete_all
seed_user.subscriptions.where(name: seeded_template_names[:subscriptions]).delete_all
seed_user.monthly_bills.where(name: seeded_template_names[:monthly_bills]).delete_all
seed_user.payment_plans.where(name: seeded_template_names[:payment_plans]).delete_all
seed_user.credit_cards.where(name: seeded_template_names[:credit_cards]).delete_all
cleared_seed_entries = seed_user.expense_entries.where(source_file: [ seed_source, seed_buffer_source ]).delete_all
cleared_seed_months = seed_user.budget_months.where(month_on: seeded_history_months).destroy_all.count
seeded_account_ids = seed_user.accounts.where(name: seeded_account_names).pluck(:id)
seed_user.account_snapshots.where(account_id: seeded_account_ids).delete_all if seeded_account_ids.any?
seed_user.accounts.where(id: seeded_account_ids).delete_all if seeded_account_ids.any?

puts "- Cleared #{cleared_seed_entries} previously seeded entr#{cleared_seed_entries == 1 ? 'y' : 'ies'}"
puts "- Cleared #{cleared_seed_months} previously seeded budget month entr#{cleared_seed_months == 1 ? 'y' : 'ies'}"

template_upsert = lambda do |scope, lookup_attrs, assign_attrs = {}|
  record = scope.find_or_initialize_by(lookup_attrs)
  record.assign_attributes(assign_attrs)
  record.save!
  record
end

seeded_accounts = [
  {
    attrs: {
      name: "Everyday Checking",
      institution_name: "Chase",
      kind: :checking,
      include_in_net_worth: true,
      include_in_cash: true,
      active: true,
      notes: "Primary spending account"
    },
    snapshots: [
      { recorded_on: Date.new(2026, 1, 31), balance: 4250.32, available_balance: 4210.32, notes: "Month-end cash" },
      { recorded_on: Date.new(2026, 2, 28), balance: 4630.11, available_balance: 4590.11, notes: "Month-end cash" },
      { recorded_on: Date.new(2026, 3, 31), balance: 5084.46, available_balance: 5044.46, notes: "Month-end cash" }
    ]
  },
  {
    attrs: {
      name: "Emergency Savings",
      institution_name: "Ally",
      kind: :savings,
      include_in_net_worth: true,
      include_in_cash: true,
      active: true,
      notes: "Cash reserve"
    },
    snapshots: [
      { recorded_on: Date.new(2026, 1, 31), balance: 15000.0, notes: "Emergency fund" },
      { recorded_on: Date.new(2026, 2, 28), balance: 15600.0, notes: "Emergency fund" },
      { recorded_on: Date.new(2026, 3, 31), balance: 16200.0, notes: "Emergency fund" }
    ]
  },
  {
    attrs: {
      name: "Long-Term Brokerage",
      institution_name: "Vanguard",
      kind: :brokerage,
      include_in_net_worth: true,
      include_in_cash: false,
      active: true,
      notes: "Index fund investments"
    },
    snapshots: [
      { recorded_on: Date.new(2026, 1, 31), balance: 24850.75, notes: "Month-end market value" },
      { recorded_on: Date.new(2026, 2, 28), balance: 25540.19, notes: "Month-end market value" },
      { recorded_on: Date.new(2026, 3, 31), balance: 26210.44, notes: "Month-end market value" }
    ]
  },
  {
    attrs: {
      name: "401(k) Portfolio",
      institution_name: "Fidelity",
      kind: :retirement,
      include_in_net_worth: true,
      include_in_cash: false,
      active: true,
      notes: "Employer retirement account"
    },
    snapshots: [
      { recorded_on: Date.new(2026, 1, 31), balance: 44200.11, notes: "Statement balance" },
      { recorded_on: Date.new(2026, 2, 28), balance: 44880.47, notes: "Statement balance" },
      { recorded_on: Date.new(2026, 3, 31), balance: 45530.92, notes: "Statement balance" }
    ]
  },
  {
    attrs: {
      name: "Wallet Cash",
      institution_name: "On Hand",
      kind: :cash,
      include_in_net_worth: true,
      include_in_cash: true,
      active: true,
      notes: "Cash on hand"
    },
    snapshots: [
      { recorded_on: Date.new(2026, 1, 31), balance: 120.0, notes: "Cash on hand" },
      { recorded_on: Date.new(2026, 2, 28), balance: 145.0, notes: "Cash on hand" },
      { recorded_on: Date.new(2026, 3, 31), balance: 110.0, notes: "Cash on hand" }
    ]
  },
  {
    attrs: {
      name: "Car Value",
      institution_name: "Kelley Blue Book",
      kind: :other_asset,
      include_in_net_worth: true,
      include_in_cash: false,
      active: true,
      notes: "Estimated vehicle value"
    },
    snapshots: [
      { recorded_on: Date.new(2026, 1, 31), balance: 16200.0, notes: "Estimated market value" },
      { recorded_on: Date.new(2026, 2, 28), balance: 16050.0, notes: "Estimated market value" },
      { recorded_on: Date.new(2026, 3, 31), balance: 15900.0, notes: "Estimated market value" }
    ]
  },
  {
    attrs: {
      name: "Rewards Visa Balance",
      institution_name: "Chase",
      kind: :credit_card,
      include_in_net_worth: true,
      include_in_cash: false,
      active: true,
      notes: "Liability account for card balance"
    },
    snapshots: [
      { recorded_on: Date.new(2026, 1, 31), balance: -980.24, notes: "Statement balance" },
      { recorded_on: Date.new(2026, 2, 28), balance: -740.91, notes: "Statement balance" },
      { recorded_on: Date.new(2026, 3, 31), balance: -412.38, notes: "Statement balance" }
    ]
  },
  {
    attrs: {
      name: "Student Loan Balance",
      institution_name: "MOHELA",
      kind: :loan,
      include_in_net_worth: true,
      include_in_cash: false,
      active: true,
      notes: "Remaining student loan principal"
    },
    snapshots: [
      { recorded_on: Date.new(2026, 1, 31), balance: -12300.0, notes: "Loan principal" },
      { recorded_on: Date.new(2026, 2, 28), balance: -12110.0, notes: "Loan principal" },
      { recorded_on: Date.new(2026, 3, 31), balance: -11920.0, notes: "Loan principal" }
    ]
  },
  {
    attrs: {
      name: "Home Repair Reserve",
      institution_name: "House Ledger",
      kind: :other_liability,
      include_in_net_worth: true,
      include_in_cash: false,
      active: true,
      notes: "Planned liability for upcoming repairs"
    },
    snapshots: [
      { recorded_on: Date.new(2026, 1, 31), balance: -3200.0, notes: "Estimated obligation" },
      { recorded_on: Date.new(2026, 2, 28), balance: -3000.0, notes: "Estimated obligation" },
      { recorded_on: Date.new(2026, 3, 31), balance: -2850.0, notes: "Estimated obligation" }
    ]
  }
]

seeded_accounts.each do |account_seed|
  account = seed_user.accounts.create!(account_seed[:attrs])
  account_seed[:snapshots].each do |snapshot_attrs|
    account.account_snapshots.create!(snapshot_attrs)
  end
end

accounts_by_name = seed_user.accounts.index_by(&:name)

template_upsert.call(
  seed_user.pay_schedules,
  { name: "Main Paycheck" },
  {
    cadence: :semimonthly,
    amount: 2500,
    first_pay_on: Date.new(2026, 1, 15),
    day_of_month_one: 15,
    day_of_month_two: 30,
    weekend_adjustment: :previous_friday,
    linked_account: accounts_by_name.fetch("Everyday Checking"),
    account: "Everyday Checking",
    active: true
  }
)

template_upsert.call(
  seed_user.pay_schedules,
  { name: "Side Hustle Paycheck" },
  {
    cadence: :monthly,
    amount: 650,
    first_pay_on: Date.new(2026, 1, 28),
    day_of_month_one: 28,
    weekend_adjustment: :next_monday,
    linked_account: accounts_by_name.fetch("Emergency Savings"),
    account: "Emergency Savings",
    active: true
  }
)

[
  {
    name: "Streaming Service",
    amount: 21.19,
    due_day: 19,
    linked_account: accounts_by_name.fetch("Rewards Visa Balance"),
    account: "Rewards Visa Balance",
    notes: "Streaming subscription"
  },
  {
    name: "Cloud Storage",
    amount: 24.99,
    due_day: 25,
    linked_account: accounts_by_name.fetch("Rewards Visa Balance"),
    account: "Rewards Visa Balance",
    notes: "Cloud storage"
  },
  {
    name: "Device Backup",
    amount: 1.00,
    due_day: 24,
    linked_account: accounts_by_name.fetch("Rewards Visa Balance"),
    account: "Rewards Visa Balance",
    notes: "Device backup"
  }
].each do |subscription_attrs|
  template_upsert.call(
    seed_user.subscriptions,
    { name: subscription_attrs[:name] },
    subscription_attrs.merge(active: true)
  )
end

[
  {
    name: "Housing Payment",
    kind: :fixed_payment,
    default_amount: 1850,
    due_day: 1,
    linked_account: accounts_by_name.fetch("Everyday Checking"),
    account: "Everyday Checking",
    notes: "Housing",
    billing_frequency: :monthly
  },
  {
    name: "Electric",
    kind: :variable_bill,
    default_amount: 135,
    due_day: 18,
    linked_account: accounts_by_name.fetch("Everyday Checking"),
    account: "Everyday Checking",
    notes: "Utility estimate",
    billing_frequency: :monthly
  },
  {
    name: "Car Insurance",
    kind: :fixed_payment,
    default_amount: 110,
    due_day: 7,
    linked_account: accounts_by_name.fetch("Everyday Checking"),
    account: "Everyday Checking",
    notes: "Quarterly insurance premium",
    billing_frequency: :quarterly,
    billing_months: [ 1, 4, 7, 10 ]
  },
  {
    name: "Property Taxes",
    kind: :fixed_payment,
    default_amount: 420,
    due_day: 10,
    linked_account: accounts_by_name.fetch("Home Repair Reserve"),
    account: "Home Repair Reserve",
    notes: "Semiannual property tax reserve",
    billing_frequency: :semiannual,
    billing_months: [ 1, 7 ]
  }
].each do |bill_attrs|
  template_upsert.call(
    seed_user.monthly_bills,
    { name: bill_attrs[:name] },
    bill_attrs.merge(active: true)
  )
end

[
  {
    name: "Installment Plan",
    total_due: 2400,
    amount_paid: 600,
    monthly_target: 200,
    due_day: 20,
    linked_account: accounts_by_name.fetch("Home Repair Reserve"),
    account: "Everyday Checking",
    notes: "Sample installment plan"
  },
  {
    name: "Student Loan",
    total_due: 18000,
    amount_paid: 6080,
    monthly_target: 190,
    due_day: 14,
    linked_account: accounts_by_name.fetch("Student Loan Balance"),
    account: "Everyday Checking",
    notes: "Ongoing student loan payment"
  }
].each do |plan_attrs|
  template_upsert.call(
    seed_user.payment_plans,
    { name: plan_attrs[:name] },
    plan_attrs.merge(active: true)
  )
end

[
  {
    name: "Everyday Visa",
    minimum_payment: 45,
    due_day: 18,
    priority: 1,
    linked_account: accounts_by_name.fetch("Rewards Visa Balance"),
    payment_account: accounts_by_name.fetch("Everyday Checking"),
    account: "Everyday Checking",
    notes: "Seeded starter card"
  },
  {
    name: "Rewards Mastercard",
    minimum_payment: 35,
    due_day: 24,
    priority: 2,
    linked_account: accounts_by_name.fetch("Rewards Visa Balance"),
    payment_account: accounts_by_name.fetch("Everyday Checking"),
    account: "Everyday Checking",
    notes: "Backup rewards card"
  }
].each do |card_attrs|
  template_upsert.call(
    seed_user.credit_cards,
    { name: card_attrs[:name] },
    card_attrs.merge(active: true)
  )
end

puts "- Starter templates ready: #{seed_user.pay_schedules.count} pay schedules, #{seed_user.subscriptions.count} subscriptions, #{seed_user.monthly_bills.count} monthly bills, #{seed_user.payment_plans.count} payment plans, #{seed_user.credit_cards.count} credit cards"
puts "- Seeded #{seed_user.accounts.count} manual accounts with #{seed_user.account_snapshots.count} balance snapshots"

if seed_transactions
  budget_months = seeded_history_months.map do |month_on|
    seed_user.budget_months.find_or_create_by!(month_on: month_on) do |month|
      month.label = month_on.strftime("%B %Y")
      month.notes = "Seeded demo month generated from planning templates and manual account activity."
    end
  end

  puts "- Prepared #{budget_months.count} budget month entr#{budget_months.count == 1 ? 'y' : 'ies'} for #{seed_user.email}"
  manual_entry_count = 0

  budget_months.each_with_index do |budget_month, index|
    GenerateMonthPaychecks.new(budget_month: budget_month).call
    GenerateMonthSubscriptions.new(budget_month: budget_month).call
    GenerateMonthMonthlyBills.new(budget_month: budget_month).call
    GenerateMonthPaymentPlans.new(budget_month: budget_month).call

    checking_account = accounts_by_name.fetch("Everyday Checking")
    credit_card_account = accounts_by_name.fetch("Rewards Visa Balance")
    savings_account = accounts_by_name.fetch("Emergency Savings")
    brokerage_account = accounts_by_name.fetch("Long-Term Brokerage")

    [
      {
        occurred_on: budget_month.month_on.change(day: 5),
        section: :variable,
        category: "Groceries",
        payee: "Neighborhood Market",
        planned_amount: BigDecimal("420") + index * 14,
        actual_amount: BigDecimal("418") + index * 14,
        source_account: checking_account,
        status: :paid,
        need_or_want: "Need",
        notes: "Seeded grocery spending",
        source_file: seed_source
      },
      {
        occurred_on: budget_month.month_on.change(day: 9),
        section: :variable,
        category: "Fuel",
        payee: "Fuel Stop",
        planned_amount: BigDecimal("78") + index * 3,
        actual_amount: BigDecimal("76") + index * 3,
        source_account: checking_account,
        status: :paid,
        need_or_want: "Need",
        notes: "Seeded transportation spending",
        source_file: seed_source
      },
      {
        occurred_on: budget_month.month_on.change(day: 12),
        section: :variable,
        category: "Dining",
        payee: "Dinner Out",
        planned_amount: BigDecimal("92") + index * 5,
        actual_amount: BigDecimal("89") + index * 5,
        source_account: credit_card_account,
        status: :paid,
        need_or_want: "Want",
        notes: "Seeded discretionary card spending",
        source_file: seed_source
      },
      {
        occurred_on: budget_month.month_on.change(day: 16),
        section: :manual,
        category: "Savings",
        payee: "Emergency Savings Transfer",
        planned_amount: BigDecimal("250") + index * 10,
        actual_amount: BigDecimal("250") + index * 10,
        source_account: savings_account,
        status: :paid,
        need_or_want: "Need",
        notes: "Seeded savings transfer",
        source_file: seed_source
      },
      {
        occurred_on: budget_month.month_on.change(day: 23),
        section: :manual,
        category: "Investing",
        payee: "Brokerage Contribution",
        planned_amount: BigDecimal("300") + index * 15,
        actual_amount: BigDecimal("300") + index * 15,
        source_account: brokerage_account,
        status: :paid,
        need_or_want: "Need",
        notes: "Seeded investment contribution",
        source_file: seed_source
      }
    ].each do |entry_attrs|
      budget_month.expense_entries.create!(
        occurred_on: entry_attrs[:occurred_on],
        section: entry_attrs[:section],
        category: entry_attrs[:category],
        payee: entry_attrs[:payee],
        planned_amount: entry_attrs[:planned_amount],
        actual_amount: entry_attrs[:actual_amount],
        source_account: entry_attrs[:source_account],
        account: entry_attrs[:source_account].name,
        status: entry_attrs[:status],
        need_or_want: entry_attrs[:need_or_want],
        notes: entry_attrs[:notes],
        source_file: entry_attrs[:source_file]
      )
      manual_entry_count += 1
    end

    if index == 1
      budget_month.expense_entries.create!(
        occurred_on: budget_month.month_on.change(day: 11),
        section: :income,
        category: "Bonus",
        payee: "Performance Bonus",
        planned_amount: BigDecimal("1800"),
        actual_amount: BigDecimal("1800"),
        source_account: checking_account,
        account: checking_account.name,
        status: :paid,
        need_or_want: "Need",
        notes: "Seeded one-time bonus income",
        source_file: seed_source
      )
      manual_entry_count += 1
    end

    if index == 3
      budget_month.expense_entries.create!(
        occurred_on: budget_month.month_on.change(day: 21),
        section: :manual,
        category: "Home Repair",
        payee: "Emergency Plumber",
        planned_amount: BigDecimal("640"),
        actual_amount: BigDecimal("615"),
        source_account: checking_account,
        account: checking_account.name,
        status: :paid,
        need_or_want: "Need",
        notes: "Seeded one-time home repair payment",
        source_file: seed_source
      )
      manual_entry_count += 1
    end

    EstimateMonthCreditCards.new(budget_month: budget_month).call
    AutoCompleteRecurringEntries.new(entries: budget_month.expense_entries, as_of: budget_month.month_on.end_of_month).call
  end

  puts "- Added #{manual_entry_count} seeded manual entr#{manual_entry_count == 1 ? 'y' : 'ies'} across generated month history"

  buffer_entries_created = 0

  budget_months.each do |budget_month|
    leftover = budget_month.calculated_leftover.to_d
    next if leftover >= target_leftover

    buffer_amount = (target_leftover - leftover).round(2)
    budget_month.expense_entries.create!(
      occurred_on: budget_month.month_on.end_of_month,
      section: :income,
      category: "Seed Adjustment",
      payee: "Cashflow Buffer",
      planned_amount: buffer_amount,
      actual_amount: buffer_amount,
      account: "Checking",
      status: :paid,
      need_or_want: "Need",
      notes: "Automatically added so demo seed data shows positive cashflow.",
      source_file: seed_buffer_source
    )
    buffer_entries_created += 1
  end

  puts "- Added #{buffer_entries_created} cashflow buffer entr#{buffer_entries_created == 1 ? 'y' : 'ies'} to keep demo data cashflow positive"
else
  puts "- Users-only mode selected; skipping generated budget months while keeping seeded templates and account demo data"
end

puts "Seed complete."
puts "Demo user: #{seed_email} / #{seed_password}"
