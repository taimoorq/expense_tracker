require "csv"

seed_file = Rails.root.join("db/seeds/march_2026_transactions.csv")
seed_source = "seed:march_2026_inflated_income_60"
income_multiplier = BigDecimal("1.6")
seed_email = ENV.fetch("SEED_USER_EMAIL", "demo@example.com")
seed_password = ENV.fetch("SEED_USER_PASSWORD", "password123!")

seed_user = User.find_or_initialize_by(email: seed_email)
if seed_user.new_record?
	seed_user.password = seed_password
	seed_user.password_confirmation = seed_password
	seed_user.save!
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

parsed_months = rows.filter_map do |row|
	month_value = row["Month"].to_s.strip
	next if month_value.blank?

	begin
		Date.strptime("#{month_value}-01", "%Y-%m-%d").beginning_of_month
	rescue ArgumentError
		nil
	end
end.uniq

budget_months = parsed_months.map do |month_on|
	seed_user.budget_months.find_or_create_by!(month_on: month_on) do |month|
		month.label = month_on.strftime("%B %Y")
	end
end

seed_user.budget_months.where(id: budget_months.map(&:id)).find_each do |month|
	month.expense_entries.where(source_file: seed_source).delete_all
end

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

puts "Seeded #{rows_created} March 2026 entries with income inflated by 60%."
puts "Demo user: #{seed_email} / #{seed_password}"
