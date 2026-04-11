require "csv"

module Budgeting
  class CsvBudgetImporter
    def initialize(file:, user:)
      @file = file
      @user = user
    end

    def call
      data = CSV.read(@file.path, headers: true)
      return { ok: false, error: "CSV has no headers." } if data.headers.blank?

      if data.headers.include?("Section")
        import_transactions(data)
      else
        import_summary(data)
      end
    rescue => error
      { ok: false, error: error.message }
    end

    private

    def import_transactions(data)
      months_touched = {}
      created_entries = 0

      data.each do |row|
        month_value = row["Month"].to_s.strip
        next if month_value.blank?

        month_on = Date.strptime("#{month_value}-01", "%Y-%m-%d")
        budget_month = find_or_build_month(month_on)
        months_touched[budget_month.id || budget_month.month_on.to_s] = true

        section_key = normalize_section(row["Section"])
        status_key = normalize_status(row["Status"])

        budget_month.expense_entries.create!(
          occurred_on: parse_date(row["Date"]),
          section: section_key,
          category: row["Category"],
          payee: row["Payee"],
          planned_amount: parse_amount(row["Planned Amount"]),
          actual_amount: parse_amount(row["Actual Amount"]),
          account: row["Account"],
          status: status_key,
          need_or_want: row["Need or Want"],
          notes: row["Notes"],
          source_file: @file.original_filename
        )
        created_entries += 1
      end

      { ok: true, months: months_touched.count, entries: created_entries }
    end

    def import_summary(data)
      months_touched = {}

      data.each do |row|
        month_label = row["Month"].to_s.strip
        next if month_label.blank?

        month_on = Date.parse("1 #{month_label}")
        budget_month = find_or_build_month(month_on)

        budget_month.leftover = parse_amount(row["Leftover"]) if row.headers.include?("Leftover")
        budget_month.save!
        months_touched[budget_month.id] = true
      end

      { ok: true, months: months_touched.count, entries: 0 }
    end

    def find_or_build_month(month_on)
      @user.budget_months.find_or_create_by!(month_on: month_on.beginning_of_month) do |month|
        month.label = month_on.strftime("%B %Y")
      end
    end

    def parse_date(value)
      text = value.to_s.strip
      return nil if text.blank?

      Date.parse(text)
    rescue
      nil
    end

    def parse_amount(value)
      text = value.to_s.gsub(/[,$]/, "").strip
      return nil if text.blank?

      BigDecimal(text)
    rescue
      nil
    end

    def normalize_section(section)
      key = section.to_s.downcase.strip
      return "income" if key == "income"
      return "fixed" if key == "fixed"
      return "variable" if key == "variable"
      return "debt" if key == "debt"
      return "manual" if key == "manual"
      return "auto" if key == "auto"

      "other"
    end

    def normalize_status(status)
      key = status.to_s.downcase.strip
      return "paid" if key == "paid"
      return "skipped" if key == "skipped"

      "planned"
    end
  end
end
