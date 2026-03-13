require "csv"

seed_file = Rails.root.join("db/seeds/march_2026_transactions.csv")
seed_source = "seed:march_2026_inflated_income_60"
seed_buffer_source = "seed:cashflow_buffer"
income_multiplier = BigDecimal("1.6")
target_leftover = BigDecimal("1200")
seed_email = ENV.fetch("SEED_USER_EMAIL", "demo@example.com")
seed_password = ENV.fetch("SEED_USER_PASSWORD", "password123!")

puts "Seeding Expense Tracker demo data..."
puts "- Demo user email: #{seed_email}"
puts "- Seed transaction file: #{seed_file.relative_path_from(Rails.root)}"

seed_user = User.find_or_initialize_by(email: seed_email)
user_status = seed_user.new_record? ? "created" : "updated"

if seed_user.new_record? || !seed_user.valid_password?(seed_password)
	seed_user.password = seed_password
	seed_user.password_confirmation = seed_password
	seed_user.save!
end

puts "- Demo user #{user_status}: #{seed_user.email}"

template_upsert = lambda do |scope, lookup_attrs, assign_attrs = {}|
	record = scope.find_or_initialize_by(lookup_attrs)
	record.assign_attributes(assign_attrs)
	record.save!
	record
end

seed_user.pay_schedules.where(name: ["Primary Paycheck"]).delete_all
seed_user.subscriptions.where(name: ["Netflix", "Google One", "Apple iCloud"]).delete_all
seed_user.monthly_bills.where(name: ["Rent"]).delete_all
seed_user.payment_plans.where(name: ["Tax Payment Plan"]).delete_all
seed_user.credit_cards.where(name: ["Visa Everyday", "Chase Freedom"]).delete_all

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
		notes: "IRS installment plan",
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

unless File.exist?(seed_file)
	puts "Seed file not found: #{seed_file}"
	return
end

rows = CSV.read(seed_file, headers: true)
if rows.headers.blank?
	puts "Seed CSV has no headers."
	return
end

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

cleared_seed_entries = 0
seed_user.budget_months.where(id: budget_months.map(&:id)).find_each do |month|
	cleared_seed_entries += month.expense_entries.where(source_file: seed_source).delete_all
	cleared_seed_entries += month.expense_entries.where(source_file: seed_buffer_source).delete_all
end

puts "- Cleared #{cleared_seed_entries} previously seeded entr#{cleared_seed_entries == 1 ? 'y' : 'ies'}"

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
puts "Seed complete."
puts "Demo user: #{seed_email} / #{seed_password}"
