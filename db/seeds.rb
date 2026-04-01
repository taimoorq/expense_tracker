seed_mode = ENV.fetch("SEED_MODE", "users").to_s.strip.presence || "users"
seed_profile = ENV.fetch("SEED_PROFILE", "demo").to_s.strip.presence || "demo"
seed_password = ENV.fetch("SEED_USER_PASSWORD", "password123!")
seed_email = ENV.fetch("SEED_USER_EMAIL", "demo@example.com")
admin_seed_email = ENV["ADMIN_USER_EMAIL"].to_s.strip
target_leftover = BigDecimal("1200")

valid_seed_modes = %w[users users_with_transactions]
valid_seed_profiles = %w[demo new_user recurring_heavy month_history_heavy account_heavy manual_adjustments all_test_users]

unless valid_seed_modes.include?(seed_mode)
  raise ArgumentError, "Invalid SEED_MODE=#{seed_mode.inspect}. Expected one of: #{valid_seed_modes.join(', ')}"
end

unless valid_seed_profiles.include?(seed_profile)
  raise ArgumentError, "Invalid SEED_PROFILE=#{seed_profile.inspect}. Expected one of: #{valid_seed_profiles.join(', ')}"
end

def month_start_for(offset)
  Date.current.beginning_of_month.prev_month(offset)
end

def month_end_for(offset)
  month_start_for(offset).end_of_month
end

def create_or_update_seed_user(email:, password:)
  user = User.find_or_initialize_by(email: email)
  status = user.new_record? ? "created" : "updated"

  if user.new_record? || !user.valid_password?(password)
    user.password = password
    user.password_confirmation = password
  end

  user.save!
  [ user, status ]
end

def reset_seed_user_data!(user)
  user.budget_months.destroy_all
  user.credit_cards.destroy_all
  user.payment_plans.destroy_all
  user.monthly_bills.destroy_all
  user.subscriptions.destroy_all
  user.pay_schedules.destroy_all
  user.accounts.destroy_all
end

def build_account_seeds(profile_key)
  full_accounts = [
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
        { recorded_on: month_end_for(2), balance: 4250.32, available_balance: 4210.32, notes: "Month-end cash" },
        { recorded_on: month_end_for(1), balance: 4630.11, available_balance: 4590.11, notes: "Month-end cash" },
        { recorded_on: month_end_for(0), balance: 5084.46, available_balance: 5044.46, notes: "Month-end cash" }
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
        { recorded_on: month_end_for(2), balance: 15000.0, notes: "Emergency fund" },
        { recorded_on: month_end_for(1), balance: 15600.0, notes: "Emergency fund" },
        { recorded_on: month_end_for(0), balance: 16200.0, notes: "Emergency fund" }
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
        { recorded_on: month_end_for(2), balance: 24850.75, notes: "Month-end market value" },
        { recorded_on: month_end_for(1), balance: 25540.19, notes: "Month-end market value" },
        { recorded_on: month_end_for(0), balance: 26210.44, notes: "Month-end market value" }
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
        { recorded_on: month_end_for(2), balance: 44200.11, notes: "Statement balance" },
        { recorded_on: month_end_for(1), balance: 44880.47, notes: "Statement balance" },
        { recorded_on: month_end_for(0), balance: 45530.92, notes: "Statement balance" }
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
        { recorded_on: month_end_for(2), balance: 120.0, notes: "Cash on hand" },
        { recorded_on: month_end_for(1), balance: 145.0, notes: "Cash on hand" },
        { recorded_on: month_end_for(0), balance: 110.0, notes: "Cash on hand" }
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
        { recorded_on: month_end_for(2), balance: 16200.0, notes: "Estimated market value" },
        { recorded_on: month_end_for(1), balance: 16050.0, notes: "Estimated market value" },
        { recorded_on: month_end_for(0), balance: 15900.0, notes: "Estimated market value" }
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
        { recorded_on: month_end_for(2), balance: -980.24, notes: "Statement balance" },
        { recorded_on: month_end_for(1), balance: -740.91, notes: "Statement balance" },
        { recorded_on: month_end_for(0), balance: -412.38, notes: "Statement balance" }
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
        { recorded_on: month_end_for(2), balance: -12300.0, notes: "Loan principal" },
        { recorded_on: month_end_for(1), balance: -12110.0, notes: "Loan principal" },
        { recorded_on: month_end_for(0), balance: -11920.0, notes: "Loan principal" }
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
        { recorded_on: month_end_for(2), balance: -3200.0, notes: "Estimated obligation" },
        { recorded_on: month_end_for(1), balance: -3000.0, notes: "Estimated obligation" },
        { recorded_on: month_end_for(0), balance: -2850.0, notes: "Estimated obligation" }
      ]
    }
  ]

  return [
    {
      attrs: {
        name: "Starter Checking",
        institution_name: "Local Credit Union",
        kind: :checking,
        include_in_net_worth: true,
        include_in_cash: true,
        active: true,
        notes: "Single starter account for first-run testing"
      },
      snapshots: []
    }
  ] if profile_key == :new_user

  return full_accounts unless profile_key == :account_heavy

  full_accounts + [
    {
      attrs: {
        name: "Travel Savings",
        institution_name: "Capital One",
        kind: :savings,
        include_in_net_worth: true,
        include_in_cash: true,
        active: true,
        notes: "Dedicated travel sinking fund"
      },
      snapshots: [
        { recorded_on: month_end_for(5), balance: 1800.0, notes: "Travel fund" },
        { recorded_on: month_end_for(4), balance: 2250.0, notes: "Travel fund" },
        { recorded_on: month_end_for(3), balance: 2410.0, notes: "Travel fund" },
        { recorded_on: month_end_for(2), balance: 2680.0, notes: "Travel fund" },
        { recorded_on: month_end_for(1), balance: 2955.0, notes: "Travel fund" },
        { recorded_on: month_end_for(0), balance: 3180.0, notes: "Travel fund" }
      ]
    },
    {
      attrs: {
        name: "HELOC Balance",
        institution_name: "Regional Bank",
        kind: :other_liability,
        include_in_net_worth: true,
        include_in_cash: false,
        active: true,
        notes: "Home equity line used for renovations"
      },
      snapshots: [
        { recorded_on: month_end_for(5), balance: -8200.0, notes: "Statement balance" },
        { recorded_on: month_end_for(4), balance: -7900.0, notes: "Statement balance" },
        { recorded_on: month_end_for(3), balance: -7600.0, notes: "Statement balance" },
        { recorded_on: month_end_for(2), balance: -7340.0, notes: "Statement balance" },
        { recorded_on: month_end_for(1), balance: -7105.0, notes: "Statement balance" },
        { recorded_on: month_end_for(0), balance: -6890.0, notes: "Statement balance" }
      ]
    }
  ]
end

def seed_accounts_for!(user, profile_key:)
  build_account_seeds(profile_key).each do |account_seed|
    account = user.accounts.create!(account_seed[:attrs])
    Array(account_seed[:snapshots]).each do |snapshot_attrs|
      account.account_snapshots.create!(snapshot_attrs)
    end
  end

  user.accounts.index_by(&:name)
end

def standard_template_sets(accounts_by_name)
  {
    pay_schedules: [
      {
        name: "Main Paycheck",
        cadence: :semimonthly,
        amount: 2500,
        first_pay_on: month_start_for(2).change(day: 15),
        day_of_month_one: 15,
        day_of_month_two: 30,
        weekend_adjustment: :previous_friday,
        linked_account: accounts_by_name.fetch("Everyday Checking"),
        account: "Everyday Checking",
        active: true
      },
      {
        name: "Side Hustle Paycheck",
        cadence: :monthly,
        amount: 650,
        first_pay_on: month_start_for(2).change(day: 28),
        day_of_month_one: 28,
        weekend_adjustment: :next_monday,
        linked_account: accounts_by_name.fetch("Emergency Savings"),
        account: "Emergency Savings",
        active: true
      }
    ],
    subscriptions: [
      {
        name: "Streaming Service",
        amount: 21.19,
        due_day: 19,
        linked_account: accounts_by_name.fetch("Rewards Visa Balance"),
        account: "Rewards Visa Balance",
        notes: "Streaming subscription",
        active: true
      },
      {
        name: "Cloud Storage",
        amount: 24.99,
        due_day: 25,
        linked_account: accounts_by_name.fetch("Rewards Visa Balance"),
        account: "Rewards Visa Balance",
        notes: "Cloud storage",
        active: true
      },
      {
        name: "Device Backup",
        amount: 1.00,
        due_day: 24,
        linked_account: accounts_by_name.fetch("Rewards Visa Balance"),
        account: "Rewards Visa Balance",
        notes: "Device backup",
        active: true
      }
    ],
    monthly_bills: [
      {
        name: "Housing Payment",
        kind: :fixed_payment,
        default_amount: 1850,
        due_day: 1,
        linked_account: accounts_by_name.fetch("Everyday Checking"),
        account: "Everyday Checking",
        notes: "Housing",
        billing_frequency: :monthly,
        active: true
      },
      {
        name: "Electric",
        kind: :variable_bill,
        default_amount: 135,
        due_day: 18,
        linked_account: accounts_by_name.fetch("Everyday Checking"),
        account: "Everyday Checking",
        notes: "Utility estimate",
        billing_frequency: :monthly,
        active: true
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
        billing_months: [ 1, 4, 7, 10 ],
        active: true
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
        billing_months: [ 1, 7 ],
        active: true
      }
    ],
    payment_plans: [
      {
        name: "Installment Plan",
        total_due: 2400,
        amount_paid: 600,
        monthly_target: 200,
        due_day: 20,
        linked_account: accounts_by_name.fetch("Home Repair Reserve"),
        account: "Everyday Checking",
        notes: "Sample installment plan",
        active: true
      },
      {
        name: "Student Loan",
        total_due: 18000,
        amount_paid: 6080,
        monthly_target: 190,
        due_day: 14,
        linked_account: accounts_by_name.fetch("Student Loan Balance"),
        account: "Everyday Checking",
        notes: "Ongoing student loan payment",
        active: true
      }
    ],
    credit_cards: [
      {
        name: "Everyday Visa",
        minimum_payment: 45,
        due_day: 18,
        priority: 1,
        linked_account: accounts_by_name.fetch("Rewards Visa Balance"),
        payment_account: accounts_by_name.fetch("Everyday Checking"),
        account: "Everyday Checking",
        notes: "Seeded starter card",
        active: true
      },
      {
        name: "Rewards Mastercard",
        minimum_payment: 35,
        due_day: 24,
        priority: 2,
        linked_account: accounts_by_name.fetch("Rewards Visa Balance"),
        payment_account: accounts_by_name.fetch("Everyday Checking"),
        account: "Everyday Checking",
        notes: "Backup rewards card",
        active: true
      }
    ]
  }
end

def heavy_template_sets(accounts_by_name)
  sets = standard_template_sets(accounts_by_name)

  sets[:pay_schedules] += [
    {
      name: "Quarterly Bonus",
      cadence: :monthly,
      amount: 850,
      first_pay_on: month_start_for(2).change(day: 10),
      day_of_month_one: 10,
      weekend_adjustment: :no_adjustment,
      linked_account: accounts_by_name.fetch("Long-Term Brokerage"),
      account: "Long-Term Brokerage",
      active: true
    }
  ]

  sets[:subscriptions] += [
    { name: "Gym Membership", amount: 49.00, due_day: 4, linked_account: accounts_by_name.fetch("Everyday Checking"), account: "Everyday Checking", notes: "Fitness", active: true },
    { name: "Music Streaming", amount: 10.99, due_day: 6, linked_account: accounts_by_name.fetch("Rewards Visa Balance"), account: "Rewards Visa Balance", notes: "Music", active: true },
    { name: "News Subscription", amount: 14.99, due_day: 8, linked_account: accounts_by_name.fetch("Rewards Visa Balance"), account: "Rewards Visa Balance", notes: "Digital news", active: true },
    { name: "Password Manager", amount: 4.99, due_day: 11, linked_account: accounts_by_name.fetch("Rewards Visa Balance"), account: "Rewards Visa Balance", notes: "Security", active: true },
    { name: "Pet Insurance", amount: 36.50, due_day: 13, linked_account: accounts_by_name.fetch("Everyday Checking"), account: "Everyday Checking", notes: "Pets", active: true },
    { name: "Design Software", amount: 32.00, due_day: 22, linked_account: accounts_by_name.fetch("Rewards Visa Balance"), account: "Rewards Visa Balance", notes: "Side gig tools", active: true }
  ]

  sets[:monthly_bills] += [
    { name: "Internet", kind: :fixed_payment, default_amount: 82, due_day: 5, linked_account: accounts_by_name.fetch("Everyday Checking"), account: "Everyday Checking", notes: "Home internet", billing_frequency: :monthly, active: true },
    { name: "Water", kind: :variable_bill, default_amount: 64, due_day: 9, linked_account: accounts_by_name.fetch("Everyday Checking"), account: "Everyday Checking", notes: "Water utility", billing_frequency: :monthly, active: true },
    { name: "Mobile Phone", kind: :fixed_payment, default_amount: 95, due_day: 12, linked_account: accounts_by_name.fetch("Everyday Checking"), account: "Everyday Checking", notes: "Family plan", billing_frequency: :monthly, active: true }
  ]

  sets[:payment_plans] += [
    { name: "Medical Installment", total_due: 1800, amount_paid: 450, monthly_target: 150, due_day: 8, linked_account: accounts_by_name.fetch("Home Repair Reserve"), account: "Everyday Checking", notes: "Clinic payment plan", active: true },
    { name: "Laptop Financing", total_due: 2200, amount_paid: 1100, monthly_target: 125, due_day: 27, linked_account: accounts_by_name.fetch("Home Repair Reserve"), account: "Everyday Checking", notes: "0% promo", active: true }
  ]

  sets[:credit_cards] += [
    { name: "Travel Rewards Visa", minimum_payment: 55, due_day: 11, priority: 3, linked_account: accounts_by_name.fetch("Rewards Visa Balance"), payment_account: accounts_by_name.fetch("Everyday Checking"), account: "Everyday Checking", notes: "Travel card", active: true },
    { name: "Store Card", minimum_payment: 28, due_day: 16, priority: 4, linked_account: accounts_by_name.fetch("Rewards Visa Balance"), payment_account: accounts_by_name.fetch("Everyday Checking"), account: "Everyday Checking", notes: "Store purchases", active: true }
  ]

  sets
end

def seed_templates_for!(user, accounts_by_name:, variant:)
  sets =
    case variant
    when :none
      { pay_schedules: [], subscriptions: [], monthly_bills: [], payment_plans: [], credit_cards: [] }
    when :heavy
      heavy_template_sets(accounts_by_name)
    else
      standard_template_sets(accounts_by_name)
    end

  sets[:pay_schedules].each { |attrs| user.pay_schedules.create!(attrs) }
  sets[:subscriptions].each { |attrs| user.subscriptions.create!(attrs) }
  sets[:monthly_bills].each { |attrs| user.monthly_bills.create!(attrs) }
  sets[:payment_plans].each { |attrs| user.payment_plans.create!(attrs) }
  sets[:credit_cards].each { |attrs| user.credit_cards.create!(attrs) }
end

def generate_seed_history_for!(user, accounts_by_name:, months_count:, source_prefix:, target_leftover:)
  manual_entry_count = 0
  buffer_entries_created = 0
  budget_months = (1..months_count).map { |offset| month_start_for(offset) }.sort.map do |month_on|
    user.budget_months.create!(
      month_on: month_on,
      label: month_on.strftime("%B %Y"),
      notes: "Seeded demo month generated from recurring transactions and manual account activity."
    )
  end

  budget_months.each_with_index do |budget_month, index|
    GenerateMonthPaychecks.new(budget_month: budget_month).call
    GenerateMonthSubscriptions.new(budget_month: budget_month).call
    GenerateMonthMonthlyBills.new(budget_month: budget_month).call
    GenerateMonthPaymentPlans.new(budget_month: budget_month).call

    checking_account = accounts_by_name["Everyday Checking"] || accounts_by_name["Starter Checking"]
    credit_card_account = accounts_by_name["Rewards Visa Balance"] || checking_account
    savings_account = accounts_by_name["Emergency Savings"] || checking_account
    brokerage_account = accounts_by_name["Long-Term Brokerage"] || checking_account

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
        notes: "Seeded grocery spending"
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
        notes: "Seeded transportation spending"
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
        notes: "Seeded discretionary card spending"
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
        notes: "Seeded savings transfer"
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
        notes: "Seeded investment contribution"
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
        account: entry_attrs[:source_account]&.name,
        status: entry_attrs[:status],
        need_or_want: entry_attrs[:need_or_want],
        notes: entry_attrs[:notes],
        source_file: "#{source_prefix}:generated_history"
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
        account: checking_account&.name,
        status: :paid,
        need_or_want: "Need",
        notes: "Seeded one-time bonus income",
        source_file: "#{source_prefix}:generated_history"
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
        account: checking_account&.name,
        status: :paid,
        need_or_want: "Need",
        notes: "Seeded one-time home repair payment",
        source_file: "#{source_prefix}:generated_history"
      )
      manual_entry_count += 1
    end

    EstimateMonthCreditCards.new(budget_month: budget_month).call if user.credit_cards.active_only.any?
    AutoCompleteRecurringEntries.new(entries: budget_month.expense_entries, as_of: budget_month.month_on.end_of_month).call
  end

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
      account: accounts_by_name["Everyday Checking"]&.name || accounts_by_name["Starter Checking"]&.name,
      status: :paid,
      need_or_want: "Need",
      notes: "Automatically added so demo seed data shows positive cashflow.",
      source_file: "#{source_prefix}:cashflow_buffer"
    )
    buffer_entries_created += 1
  end

  { months: budget_months.count, manual_entries: manual_entry_count, buffer_entries: buffer_entries_created }
end

def add_manual_adjustment_scenarios!(user, accounts_by_name:)
  current_month = user.budget_months.order(:month_on).last
  return if current_month.blank?

  checking_account = accounts_by_name.fetch("Everyday Checking")
  credit_card = user.credit_cards.find_by!(name: "Everyday Visa")
  payment_plan = user.payment_plans.find_by!(name: "Student Loan")
  subscription = user.subscriptions.find_by!(name: "Streaming Service")

  current_month.expense_entries.create!(
    occurred_on: current_month.month_on.change(day: 22),
    section: :debt,
    category: "Credit Card",
    payee: credit_card.name,
    planned_amount: BigDecimal("125"),
    actual_amount: nil,
    source_account: checking_account,
    account: checking_account.name,
    status: :planned,
    need_or_want: "Need",
    notes: "Extra payment linked to recurring card",
    source_file: "manual",
    source_template: credit_card
  )

  current_month.expense_entries.create!(
    occurred_on: current_month.month_on.change(day: 27),
    section: :debt,
    category: "Payment Plan",
    payee: payment_plan.name,
    planned_amount: BigDecimal("75"),
    actual_amount: BigDecimal("75"),
    source_account: checking_account,
    account: checking_account.name,
    status: :paid,
    need_or_want: "Need",
    notes: "Additional manual payment tied back to the plan",
    source_file: "manual",
    source_template: payment_plan
  )

  skipped_entry = current_month.expense_entries.find_by(payee: subscription.name, source_file: "subscription")
  skipped_entry&.update!(status: :skipped, notes: "Skipped this month while traveling")
end

def seed_profile_for!(profile_key, email:, password:, seed_mode:, target_leftover:)
  user, status = create_or_update_seed_user(email: email, password: password)
  reset_seed_user_data!(user)

  case profile_key
  when :new_user
    accounts_by_name = seed_accounts_for!(user, profile_key: :new_user)
    {
      user: user,
      status: status,
      profile: profile_key,
      accounts: accounts_by_name.size,
      snapshots: user.account_snapshots.count
    }
  when :recurring_heavy
    accounts_by_name = seed_accounts_for!(user, profile_key: :full)
    seed_templates_for!(user, accounts_by_name: accounts_by_name, variant: :heavy)
    {
      user: user,
      status: status,
      profile: profile_key,
      accounts: user.accounts.count,
      recurring_total: user.pay_schedules.count + user.subscriptions.count + user.monthly_bills.count + user.payment_plans.count + user.credit_cards.count
    }
  when :month_history_heavy
    accounts_by_name = seed_accounts_for!(user, profile_key: :full)
    seed_templates_for!(user, accounts_by_name: accounts_by_name, variant: :heavy)
    history = generate_seed_history_for!(user, accounts_by_name: accounts_by_name, months_count: 12, source_prefix: "seed:month_history_heavy", target_leftover: target_leftover)
    {
      user: user,
      status: status,
      profile: profile_key
    }.merge(history)
  when :account_heavy
    accounts_by_name = seed_accounts_for!(user, profile_key: :account_heavy)
    seed_templates_for!(user, accounts_by_name: accounts_by_name, variant: :standard)
    history = generate_seed_history_for!(user, accounts_by_name: accounts_by_name, months_count: 2, source_prefix: "seed:account_heavy", target_leftover: target_leftover)
    {
      user: user,
      status: status,
      profile: profile_key,
      accounts: user.accounts.count,
      snapshots: user.account_snapshots.count
    }.merge(history)
  when :manual_adjustments
    accounts_by_name = seed_accounts_for!(user, profile_key: :full)
    seed_templates_for!(user, accounts_by_name: accounts_by_name, variant: :standard)
    history = generate_seed_history_for!(user, accounts_by_name: accounts_by_name, months_count: 3, source_prefix: "seed:manual_adjustments", target_leftover: target_leftover)
    add_manual_adjustment_scenarios!(user, accounts_by_name: accounts_by_name)
    {
      user: user,
      status: status,
      profile: profile_key
    }.merge(history)
  else
    accounts_by_name = seed_accounts_for!(user, profile_key: :full)
    seed_templates_for!(user, accounts_by_name: accounts_by_name, variant: :standard)
    history = seed_mode == "users_with_transactions" ? generate_seed_history_for!(user, accounts_by_name: accounts_by_name, months_count: 6, source_prefix: "seed:demo", target_leftover: target_leftover) : { months: 0, manual_entries: 0, buffer_entries: 0 }
    {
      user: user,
      status: status,
      profile: :demo,
      accounts: user.accounts.count,
      snapshots: user.account_snapshots.count
    }.merge(history)
  end
end

profiles_to_seed =
  if seed_profile == "all_test_users"
    [
      [ :demo, seed_email ],
      [ :new_user, "new-user@example.com" ],
      [ :recurring_heavy, "recurring-heavy@example.com" ],
      [ :month_history_heavy, "month-history@example.com" ],
      [ :account_heavy, "account-heavy@example.com" ],
      [ :manual_adjustments, "manual-adjustments@example.com" ]
    ]
  else
    [ [ seed_profile.to_sym, seed_email ] ]
  end

puts "Seeding Expense Tracker demo data..."
puts "- Seed profile: #{seed_profile}"
puts "- Seed mode: #{seed_mode}"
puts "- Admin user email: #{admin_seed_email}" if admin_seed_email.present?

admin_bootstrap_result = AdminBootstrapper.new.call
puts "- Admin user #{admin_bootstrap_result.status}: #{admin_bootstrap_result.admin_user.email}" if admin_bootstrap_result.admin_user

profiles_to_seed.each do |profile_key, email|
  result = seed_profile_for!(profile_key, email: email, password: seed_password, seed_mode: seed_mode, target_leftover: target_leftover)
  user = result.fetch(:user)

  puts "- #{profile_key.to_s.humanize} user #{result.fetch(:status)}: #{user.email}"
  puts "  Accounts: #{user.accounts.count}, snapshots: #{user.account_snapshots.count}, recurring: #{user.pay_schedules.count + user.subscriptions.count + user.monthly_bills.count + user.payment_plans.count + user.credit_cards.count}, months: #{user.budget_months.count}, entries: #{user.expense_entries.count}"
end

puts "Seed complete."
puts "Primary seed login: #{profiles_to_seed.first.last} / #{seed_password}"
