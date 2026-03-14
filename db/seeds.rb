require "csv"

seed_file = Rails.root.join("db/seeds/march_2026_transactions.csv")
seed_source = "seed:march_2026_inflated_income_60"
seed_buffer_source = "seed:cashflow_buffer"
income_multiplier = BigDecimal("1.6")
target_leftover = BigDecimal("1200")
seed_mode = ENV.fetch("SEED_MODE", "users").to_s.strip.presence || "users"
valid_seed_modes = %w[users users_with_transactions]
seed_email = ENV.fetch("SEED_USER_EMAIL", "demo@example.com")
seed_password = ENV.fetch("SEED_USER_PASSWORD", "password123!")
admin_seed_email = ENV["ADMIN_USER_EMAIL"].to_s.strip

unless valid_seed_modes.include?(seed_mode)
  raise ArgumentError, "Invalid SEED_MODE=#{seed_mode.inspect}. Expected one of: #{valid_seed_modes.join(', ')}"
end

seed_transactions = seed_mode == "users_with_transactions"

puts "Seeding Expense Tracker demo data..."
puts "- Seed mode: #{seed_mode}"
puts "- Demo user email: #{seed_email}"
puts "- Admin user email: #{admin_seed_email}" if admin_seed_email.present?
puts "- Seed transaction file: #{seed_file.relative_path_from(Rails.root)}" if seed_transactions

admin_bootstrap_result = AdminBootstrapper.new.call
puts "- Admin user #{admin_bootstrap_result.status}: #{admin_bootstrap_result.admin_user.email}" if admin_bootstrap_result.admin_user

seeded_template_names = {
  pay_schedules: [ "Primary Paycheck", "Main Paycheck" ],
  subscriptions: [ "Netflix", "Google One", "Apple iCloud", "Streaming Service", "Cloud Storage", "Device Backup" ],
  monthly_bills: [ "Rent", "Housing Payment", "Electric" ],
  payment_plans: [ "Tax Payment Plan", "Installment Plan" ],
  credit_cards: [ "Visa Everyday", "Chase Freedom", "Everyday Visa", "Rewards Mastercard" ]
}

seeded_account_names = [
  "Everyday Checking",
  "Emergency Savings",
  "Long-Term Brokerage",
  "Rewards Visa Balance"
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
seeded_account_ids = seed_user.accounts.where(name: seeded_account_names).pluck(:id)
seed_user.account_snapshots.where(account_id: seeded_account_ids).delete_all if seeded_account_ids.any?
seed_user.accounts.where(id: seeded_account_ids).delete_all if seeded_account_ids.any?

cleared_seed_entries = seed_user.expense_entries.where(source_file: [ seed_source, seed_buffer_source ]).delete_all

puts "- Cleared #{cleared_seed_entries} previously seeded entr#{cleared_seed_entries == 1 ? 'y' : 'ies'}"

if seed_transactions
  template_upsert = lambda do |scope, lookup_attrs, assign_attrs = {}|
    record = scope.find_or_initialize_by(lookup_attrs)
    record.assign_attributes(assign_attrs)
    record.save!
    record
  end

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
      account: "Checking",
      active: true
    }
  )

  [
    { name: "Streaming Service", amount: 21.19, due_day: 19, account: "Card", notes: "Streaming subscription" },
    { name: "Cloud Storage", amount: 24.99, due_day: 25, account: "Card", notes: "Cloud storage" },
    { name: "Device Backup", amount: 1.00, due_day: 24, account: "Card", notes: "Device backup" }
  ].each do |subscription_attrs|
    template_upsert.call(
      seed_user.subscriptions,
      { name: subscription_attrs[:name] },
      subscription_attrs.merge(active: true)
    )
  end

  [
    { name: "Housing Payment", kind: :fixed_payment, default_amount: 1850, due_day: 1, account: "Checking", notes: "Housing" },
    { name: "Electric", kind: :variable_bill, default_amount: 135, due_day: 18, account: "Checking", notes: "Utility estimate" }
  ].each do |bill_attrs|
    template_upsert.call(
      seed_user.monthly_bills,
      { name: bill_attrs[:name] },
      bill_attrs.merge(active: true)
    )
  end

  template_upsert.call(
    seed_user.payment_plans,
    { name: "Installment Plan" },
    {
      total_due: 2400,
      amount_paid: 600,
      monthly_target: 200,
      due_day: 20,
      account: "Checking",
      notes: "Sample installment plan",
      active: true
    }
  )

  [
    { name: "Everyday Visa", minimum_payment: 45, priority: 1, account: "Visa" },
    { name: "Rewards Mastercard", minimum_payment: 35, priority: 2, account: "Mastercard" }
  ].each do |card_attrs|
    template_upsert.call(
      seed_user.credit_cards,
      { name: card_attrs[:name] },
      card_attrs.merge(active: true, notes: "Seeded starter card")
    )
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
    }
  ]

  seeded_accounts.each do |account_seed|
    account = seed_user.accounts.create!(account_seed[:attrs])
    account_seed[:snapshots].each do |snapshot_attrs|
      account.account_snapshots.create!(snapshot_attrs)
    end
  end

  raise "Seed file not found: #{seed_file}" unless File.exist?(seed_file)

  rows = CSV.read(seed_file, headers: true)
  raise "Seed CSV has no headers." if rows.headers.blank?

  puts "- Loaded #{rows.size} transaction rows from CSV"

  parsed_months = rows.filter_map do |row|
    month_value = row["Month"].to_s.strip
    next if month_value.blank?

    begin
      Date.strptime("#{month_value}-01", "%Y-%m-%d").beginning_of_month
    rescue ArgumentError
      nil
    end
  end.uniq

  puts "- Target budget months: #{parsed_months.map { |month| month.strftime('%B %Y') }.join(', ')}"

  budget_months = parsed_months.map do |month_on|
    seed_user.budget_months.find_or_create_by!(month_on: month_on) do |month|
      month.label = month_on.strftime("%B %Y")
    end
  end

  puts "- Prepared #{budget_months.count} budget month entr#{budget_months.count == 1 ? 'y' : 'ies'} for #{seed_user.email}"

  parse_date = lambda do |value|
    text = value.to_s.strip
    next nil if text.blank?

    Date.parse(text)
  rescue ArgumentError
    nil
  end

  parse_amount = lambda do |value|
    text = value.to_s.gsub(/[,$]/, "").strip
    next nil if text.blank?

    BigDecimal(text)
  rescue ArgumentError
    nil
  end

  normalize_section = lambda do |section|
    key = section.to_s.downcase.strip
    ExpenseEntry.sections.key?(key) ? key : "other"
  end

  normalize_status = lambda do |status|
    key = status.to_s.downcase.strip
    ExpenseEntry.statuses.key?(key) ? key : "planned"
  end

  rows_created = 0

  rows.each do |row|
    month_value = row["Month"].to_s.strip
    next if month_value.blank?

    begin
      month_on = Date.strptime("#{month_value}-01", "%Y-%m-%d").beginning_of_month
    rescue ArgumentError
      next
    end

    budget_month = budget_months.find { |month| month.month_on == month_on }
    next if budget_month.blank?

    section_key = normalize_section.call(row["Section"])
    planned_amount = parse_amount.call(row["Planned Amount"])
    actual_amount = parse_amount.call(row["Actual Amount"])

    if section_key == "income"
      planned_amount = planned_amount&.*(income_multiplier)
      actual_amount = actual_amount&.*(income_multiplier)
    end

    budget_month.expense_entries.create!(
      occurred_on: parse_date.call(row["Date"]),
      section: section_key,
      category: row["Category"],
      payee: row["Payee"],
      planned_amount: planned_amount,
      actual_amount: actual_amount,
      account: row["Account"],
      status: normalize_status.call(row["Status"]),
      need_or_want: row["Need or Want"],
      notes: row["Notes"],
      source_file: seed_source
    )

    rows_created += 1
  end

  puts "- Added #{rows_created} seeded transaction entr#{rows_created == 1 ? 'y' : 'ies'}"

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
  puts "- Starter templates ready: #{seed_user.pay_schedules.count} pay schedules, #{seed_user.subscriptions.count} subscriptions, #{seed_user.monthly_bills.count} monthly bills, #{seed_user.payment_plans.count} payment plans, #{seed_user.credit_cards.count} credit cards"
  puts "- Seeded #{seed_user.accounts.count} manual accounts with #{seed_user.account_snapshots.count} balance snapshots"
else
  puts "- Users-only mode selected; skipping recurring templates, transaction import, and manual account demo data"
end

puts "Seed complete."
puts "Demo user: #{seed_email} / #{seed_password}"
