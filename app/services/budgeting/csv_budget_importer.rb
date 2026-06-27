require "csv"

module Budgeting
  class CsvBudgetImporter
    def initialize(file:, user:)
      @file = file
      @user = user
      @warnings = []
    end

    def call
      data = CSV.read(@file.path, headers: true)
      return { ok: false, error: "CSV has no headers." } if data.headers.blank?

      result = if data.headers.include?("Section")
        import_transactions(data)
      else
        import_summary(data)
      end

      result.merge(warnings: warnings)
    rescue => error
      { ok: false, error: error.message, warnings: warnings }
    end

    private

    attr_reader :warnings

    def import_transactions(data)
      months_touched = {}
      created_entries = 0

      data.each.with_index(2) do |row, row_number|
        month_value = row["Month"].to_s.strip
        next if month_value.blank?

        month_on = parse_transaction_month(month_value, row_number: row_number)
        next if month_on.blank?

        budget_month = find_or_build_month(month_on)
        months_touched[budget_month.id || budget_month.month_on.to_s] = true

        section_key = normalize_section(row["Section"])
        status_key = normalize_status(row["Status"])

        budget_month.expense_entries.create!(
          occurred_on: parse_date(row["Date"], row_number: row_number, column: "Date"),
          section: section_key,
          category: row["Category"],
          payee: row["Payee"],
          planned_amount: parse_amount(row["Planned Amount"], row_number: row_number, column: "Planned Amount"),
          actual_amount: parse_amount(row["Actual Amount"], row_number: row_number, column: "Actual Amount"),
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

      data.each.with_index(2) do |row, row_number|
        month_label = row["Month"].to_s.strip
        next if month_label.blank?

        month_on = parse_summary_month(month_label, row_number: row_number)
        next if month_on.blank?

        budget_month = find_or_build_month(month_on)

        budget_month.leftover = parse_amount(row["Leftover"], row_number: row_number, column: "Leftover") if row.headers.include?("Leftover")
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

    def parse_transaction_month(value, row_number:)
      Date.strptime("#{value}-01", "%Y-%m-%d")
    rescue ArgumentError
      warnings << "Row #{row_number}: Month must use YYYY-MM format."
      nil
    end

    def parse_summary_month(value, row_number:)
      Date.parse("1 #{value}")
    rescue ArgumentError
      warnings << "Row #{row_number}: Month could not be parsed."
      nil
    end

    def parse_date(value, row_number:, column:)
      text = value.to_s.strip
      return nil if text.blank?

      Date.parse(text)
    rescue ArgumentError
      warnings << "Row #{row_number}: #{column} could not be parsed."
      nil
    end

    def parse_amount(value, row_number:, column:)
      text = value.to_s.gsub(/[,$]/, "").strip
      return nil if text.blank?

      BigDecimal(text)
    rescue ArgumentError
      warnings << "Row #{row_number}: #{column} could not be parsed."
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
