#!/usr/bin/env ruby

require "bigdecimal"
require "csv"
require "date"
require "faker"
require "fileutils"
require "pathname"

Faker::Config.random = Random.new(42_687)

ROOT = Pathname.new(__dir__).join("..").expand_path
DEFAULT_SOURCE_DIR = ROOT.join("..", "sample_exports")
DEFAULT_OUTPUT_DIR = ROOT.join("test", "fixtures", "files", "account_activity")
GENERIC_CATEGORIES = [
  "Auto",
  "Dining",
  "Education",
  "Entertainment",
  "Fees",
  "Groceries",
  "Health",
  "Home",
  "Insurance",
  "Payments",
  "Services",
  "Shopping",
  "Travel",
  "Utilities"
].freeze
GENERIC_TYPES = {
  "payment" => "Payment",
  "return" => "Return",
  "fee" => "Fee",
  "adjustment" => "Adjustment",
  "credit" => "Credit",
  "debit" => "Debit"
}.freeze

Profile = Data.define(:key, :output_filename, :header)

PROFILES = [
  Profile.new(
    key: :signed_with_type,
    output_filename: "signed_amounts_with_type.csv",
    header: [ "Transaction Date", "Post Date", "Description", "Category", "Type", "Amount", "Memo" ]
  ),
  Profile.new(
    key: :positive_charges,
    output_filename: "positive_charges.csv",
    header: [ "Trans. Date", "Post Date", "Description", "Amount", "Category" ]
  ),
  Profile.new(
    key: :preamble_card_activity,
    output_filename: "preamble_card_activity.csv",
    header: [ "Transaction Date", "Description", "Category", "Amount", "Card Last 4 Digits", "Purchased by" ]
  ),
  Profile.new(
    key: :boa_bank_activity,
    output_filename: "boa_bank_activity.csv",
    header: [ "Date", "Description", "Amount", "Running Bal." ]
  )
].freeze

def source_dir
  Pathname.new(ARGV[0] || DEFAULT_SOURCE_DIR).expand_path
end

def output_dir
  Pathname.new(ARGV[1] || DEFAULT_OUTPUT_DIR).expand_path
end

def rows_for(path)
  lines = path.readlines
  header_index = lines.index { |line| profile_for_header(CSV.parse_line(line, liberal_parsing: true) || []) }
  raise "Could not find a supported activity CSV header in #{path}" if header_index.nil?

  csv_text = lines.drop(header_index).join
  rows = CSV.parse(csv_text, headers: true, liberal_parsing: true)
  profile = profile_for_header(rows.headers)

  [ profile, rows ]
end

def profile_for_header(header)
  normalized = Array(header).map(&:to_s)
  PROFILES.find { |profile| profile.header == normalized }
end

def fake_description(index)
  token = Faker::Number.hexadecimal(digits: 8).upcase
  "SAMPLE MERCHANT #{token} #{format('%03d', index + 1)}"
end

def fake_category(type: nil, payment_category: nil)
  return payment_category if payment_category && payment_like_type?(type)
  return "Fees" if type.to_s.downcase == "fee"
  return "Credits" if %w[return adjustment credit].include?(type.to_s.downcase)

  GENERIC_CATEGORIES.sample
end

def fake_type(original)
  key = original.to_s.downcase
  original_type = original.to_s.strip
  GENERIC_TYPES.fetch(key, original_type.empty? ? "Sale" : original_type)
end

def payment_like_type?(type)
  %w[payment return adjustment credit].include?(type.to_s.downcase)
end

def fake_amount(original, payment_like: false)
  original_amount = parse_money(original)
  sign = original_amount.negative? ? -1 : 1
  amount =
    if payment_like
      rand_money(75, 3_500)
    else
      rand_money(3, 425)
    end

  format("%.2f", amount * sign)
end

def rand_money(min, max)
  cents = Faker::Number.between(from: min * 100, to: max * 100)
  cents / 100.0
end

def fake_dates(rows, transaction_header:, post_header: nil)
  dates = rows.map { |row| parse_date(row[transaction_header]) }.compact
  descending = dates.first && dates.last && dates.first > dates.last
  span = 180
  denominator = [ rows.length - 1, 1 ].max

  rows.each_with_index.to_h do |row, index|
    offset = (index * span.to_f / denominator).round
    transaction_date = Date.new(2026, 1, 3) + (descending ? span - offset : offset)
    post_date = transaction_date + Faker::Number.between(from: 0, to: 2)

    [ row.object_id, { transaction_header => format_date(transaction_date), post_header => format_date(post_date) } ]
  end
end

def parse_date(value)
  Date.strptime(value.to_s, "%m/%d/%Y")
rescue ArgumentError
  nil
end

def format_date(date)
  date.strftime("%m/%d/%Y")
end

def sanitize_signed_with_type(rows)
  fake_dates_by_row = fake_dates(rows, transaction_header: "Transaction Date", post_header: "Post Date")

  rows.each_with_index.map do |row, index|
    type = fake_type(row["Type"])
    payment_like = payment_like_type?(row["Type"])

    {
      "Transaction Date" => fake_dates_by_row[row.object_id]["Transaction Date"],
      "Post Date" => fake_dates_by_row[row.object_id]["Post Date"],
      "Description" => fake_description(index),
      "Category" => fake_category(type: row["Type"], payment_category: "Payments"),
      "Type" => type,
      "Amount" => fake_amount(row["Amount"], payment_like: payment_like),
      "Memo" => row["Memo"].to_s.strip.empty? ? nil : Faker::Lorem.sentence(word_count: 4)
    }
  end
end

def sanitize_positive_charges(rows)
  fake_dates_by_row = fake_dates(rows, transaction_header: "Trans. Date", post_header: "Post Date")

  rows.each_with_index.map do |row, index|
    original_amount = parse_money(row["Amount"])
    payment_like = original_amount.negative?

    {
      "Trans. Date" => fake_dates_by_row[row.object_id]["Trans. Date"],
      "Post Date" => fake_dates_by_row[row.object_id]["Post Date"],
      "Description" => fake_description(index),
      "Amount" => fake_amount(row["Amount"], payment_like: payment_like),
      "Category" => payment_like ? "Payments and Credits" : fake_category
    }
  end
end

def sanitize_preamble_card_activity(rows)
  fake_dates_by_row = fake_dates(rows, transaction_header: "Transaction Date")
  last_four = fake_last_four
  purchaser = "SAMPLE USER #{Faker::Number.hexadecimal(digits: 6).upcase}"

  sanitized_rows = rows.each_with_index.map do |row, index|
    payment_like = row["Category"].to_s.casecmp("CREDIT").zero?

    {
      "Transaction Date" => fake_dates_by_row[row.object_id]["Transaction Date"],
      "Description" => fake_description(index),
      "Category" => payment_like ? "CREDIT" : "DEBIT",
      "Amount" => fake_amount(row["Amount"], payment_like: payment_like),
      "Card Last 4 Digits" => "=\"#{last_four}\"",
      "Purchased by" => purchaser
    }
  end

  [ sanitized_rows, last_four ]
end

def sanitize_boa_bank_activity(rows)
  fake_dates_by_row = fake_dates(rows, transaction_header: "Date")
  running_balance = BigDecimal(format("%.2f", rand_money(1_500, 18_000)))

  rows.each_with_index.map do |row, index|
    amount =
      if row["Amount"].to_s.strip.empty?
        nil
      else
        fake_amount(row["Amount"], payment_like: parse_money(row["Amount"]).positive?)
      end

    running_balance += BigDecimal(amount) if amount
    transaction_date = fake_dates_by_row[row.object_id]["Date"]

    {
      "Date" => transaction_date,
      "Description" => amount.nil? ? "Beginning balance as of #{transaction_date}" : fake_bank_description(index),
      "Amount" => amount,
      "Running Bal." => format_money(running_balance)
    }
  end
end

def fake_bank_description(index)
  company = Faker::Company.name.upcase.gsub(/[^A-Z0-9& ]/, "").strip.gsub(/\s+/, " ")
  token = Faker::Number.number(digits: 6)
  type = [ "ACH", "CARD", "ONLINE", "TRANSFER", "CHECK" ].sample

  "#{type} #{company} #{token} #{format('%03d', index + 1)}"
end

def fake_last_four
  Faker::Number.between(from: 6000, to: 8999).to_s
end

def write_csv(path, header, rows)
  CSV.open(path, "w", write_headers: true, headers: header) do |csv|
    rows.each { |row| csv << header.map { |column| row[column] } }
  end
end

def write_preamble_csv(path, header, rows, last_four)
  File.open(path, "w") do |file|
    file.puts "Sample Card Services"
    file.puts "Account Number: XXXXXXXXXXXX#{last_four}"
    file.puts "Account Balance as of June 30 2026:    $#{format('%.2f', rand_money(1_200, 24_000))}"
    file.puts " "
    file.write CSV.generate(write_headers: true, headers: header) { |csv| rows.each { |row| csv << header.map { |column| row[column] } } }
  end
end

def write_boa_bank_csv(path, header, rows)
  start_date = rows.first.fetch("Date")
  end_date = rows.last.fetch("Date")
  beginning_balance = BigDecimal(rows.first.fetch("Running Bal.").to_s)
  ending_balance = BigDecimal(rows.last.fetch("Running Bal.").to_s)
  credits_total = rows.sum { |row| positive_decimal(row["Amount"]) }
  debits_total = rows.sum { |row| negative_decimal(row["Amount"]) }

  File.open(path, "w") do |file|
    file.puts "Sample Bank of America"
    file.puts "Beginning balance as of #{start_date},,#{format_money(beginning_balance)}"
    file.puts "Deposits and other credits,,#{format_money(credits_total)}"
    file.puts "Withdrawals and other debits,,#{format_money(debits_total)}"
    file.puts "Ending balance as of #{end_date},,#{format_money(ending_balance)}"
    file.puts " "
    file.write CSV.generate(write_headers: true, headers: header) { |csv| rows.each { |row| csv << header.map { |column| row[column] } } }
  end
end

def format_money(value)
  format("%.2f", value.is_a?(BigDecimal) ? value : parse_money(value))
end

def positive_decimal(value)
  amount = decimal_or_zero(value)
  amount.positive? ? amount : BigDecimal("0")
end

def negative_decimal(value)
  amount = decimal_or_zero(value)
  amount.negative? ? amount : BigDecimal("0")
end

def decimal_or_zero(value)
  return BigDecimal("0") if value.to_s.strip.empty?

  parse_money(value)
rescue ArgumentError
  BigDecimal("0")
end

def parse_money(value)
  BigDecimal(value.to_s.delete("$,").strip)
end

FileUtils.mkdir_p(output_dir)

source_dir.children.select { |path| path.file? && path.extname == ".csv" }.sort.each do |path|
  profile, rows = rows_for(path)
  output_path = output_dir.join(profile.output_filename)

  case profile.key
  when :signed_with_type
    write_csv(output_path, profile.header, sanitize_signed_with_type(rows))
  when :positive_charges
    write_csv(output_path, profile.header, sanitize_positive_charges(rows))
  when :preamble_card_activity
    sanitized_rows, last_four = sanitize_preamble_card_activity(rows)
    write_preamble_csv(output_path, profile.header, sanitized_rows, last_four)
  when :boa_bank_activity
    sanitized_rows = sanitize_boa_bank_activity(rows)
    write_boa_bank_csv(output_path, profile.header, sanitized_rows)
  else
    raise "Unsupported profile #{profile.key}"
  end

  puts "Wrote #{output_path.relative_path_from(ROOT)}"
end
