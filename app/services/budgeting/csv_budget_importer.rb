require "csv"
require "set"

module Budgeting
  class CsvBudgetImporter
    SOURCE_ACCOUNT_HEADERS = [
      "Money Leaves Account",
      "Money leaves / activity account",
      "Money leaves account",
      "Activity Account",
      "Source Account"
    ].freeze
    LEGACY_ACCOUNT_HEADERS = [ "Account" ].freeze
    DESTINATION_ACCOUNT_HEADERS = [
      "Money Goes To Account",
      "Money goes to",
      "Destination Account"
    ].freeze

    def initialize(user:, file: nil, preview: nil)
      @file = file
      @user = user
      @preview = preview&.deep_symbolize_keys
    end

    def call
      plan = preview
      return failed_import_from(plan) unless plan[:ok]

      counts = { months: 0, entries: 0, duplicates: 0 }

      ApplicationRecord.transaction do
        counts = plan[:mode] == "summary" ? import_summary_rows(plan[:rows]) : import_transaction_rows(plan[:rows])
      end

      counts.merge(ok: true, warnings: Array(plan[:warnings]), errors: [])
    rescue ActiveRecord::RecordInvalid => error
      { ok: false, error: error.record.errors.full_messages.to_sentence.presence || error.message, warnings: Array(plan[:warnings]), errors: [] }
    end

    def preview
      return @preview if @preview.present?

      data = CSV.read(@file.path, headers: true)
      return { ok: false, error: "CSV has no headers." } if data.headers.blank?

      if data.headers.include?("Section")
        preview_transactions(data)
      else
        preview_summary(data)
      end
    rescue => error
      { ok: false, error: error.message, warnings: [], errors: [ error.message ], rows: [] }
    end

    private

    attr_reader :user

    def preview_transactions(data)
      warnings = []
      errors = []
      rows = []

      data.each.with_index(2) do |row, row_number|
        next if blank_row?(row)

        row_errors = []
        row_warnings = []
        month_value = row["Month"].to_s.strip
        month_on = parse_transaction_month(month_value, row_number: row_number, errors: row_errors)
        explicit_source_account_name = account_column_value(row, SOURCE_ACCOUNT_HEADERS)
        source_account_name = explicit_source_account_name.presence || account_column_value(row, LEGACY_ACCOUNT_HEADERS)
        destination_account_name = account_column_value(row, DESTINATION_ACCOUNT_HEADERS)
        parsed_row = {
          row_number: row_number,
          month_on: month_on,
          occurred_on: parse_date(row["Date"], row_number: row_number, column: "Date", errors: row_errors),
          section: normalize_section(row["Section"], row_number: row_number, warnings: row_warnings),
          category: row["Category"],
          payee: row["Payee"],
          planned_amount: parse_amount(row["Planned Amount"], row_number: row_number, column: "Planned Amount", errors: row_errors),
          actual_amount: parse_amount(row["Actual Amount"], row_number: row_number, column: "Actual Amount", errors: row_errors),
          account: source_account_name,
          source_account_name: source_account_name,
          destination_account_name: destination_account_name,
          status: normalize_status(row["Status"], row_number: row_number, warnings: row_warnings),
          need_or_want: row["Need or Want"],
          notes: row["Notes"],
          source_file: @file.original_filename
        }

        warn_unresolved_account(row_warnings, row_number, explicit_source_account_name, label: "Money leaves / activity account", fallback: "kept as a manual account label")
        warn_unresolved_account(row_warnings, row_number, destination_account_name, label: "Money goes to", fallback: "left unlinked")

        if row_errors.empty? && duplicate_transaction_row?(parsed_row)
          parsed_row[:duplicate] = true
          row_warnings << "Row #{row_number}: This looks like a duplicate of an existing entry and will be skipped."
        end

        warnings.concat(row_warnings)
        errors.concat(row_errors)
        rows << parsed_row if row_errors.empty?
      end

      preview_result(mode: "transactions", rows: rows, warnings: warnings, errors: errors)
    end

    def preview_summary(data)
      warnings = []
      errors = []
      rows = []

      data.each.with_index(2) do |row, row_number|
        next if blank_row?(row)

        row_errors = []
        month_label = row["Month"].to_s.strip
        month_on = parse_summary_month(month_label, row_number: row_number, errors: row_errors)
        parsed_row = {
          row_number: row_number,
          month_on: month_on,
          leftover: row.headers.include?("Leftover") ? parse_amount(row["Leftover"], row_number: row_number, column: "Leftover", errors: row_errors) : nil
        }

        if row_errors.empty? && user.budget_months.exists?(month_on: month_on.beginning_of_month)
          warnings << "Row #{row_number}: This month already exists and its summary will be updated."
        end

        errors.concat(row_errors)
        rows << parsed_row if row_errors.empty?
      end

      preview_result(mode: "summary", rows: rows, warnings: warnings, errors: errors)
    end

    def preview_result(mode:, rows:, warnings:, errors:)
      duplicate_count = rows.count { |row| row[:duplicate] }
      importable_entries = mode == "transactions" ? rows.count { |row| !row[:duplicate] } : 0

      {
        ok: errors.empty?,
        mode: mode,
        months: rows.map { |row| row[:month_on]&.beginning_of_month }.compact.uniq.size,
        entries: importable_entries,
        duplicates: duplicate_count,
        warnings: warnings,
        errors: errors,
        rows: rows
      }
    end

    def import_transaction_rows(rows)
      months_touched = Set.new
      created_entries = 0
      skipped_duplicates = 0

      rows.each do |raw_row|
        row = raw_row.deep_symbolize_keys
        month_on = row[:month_on].to_date
        budget_month = find_or_build_month(month_on)
        months_touched << budget_month.id

        if duplicate_transaction_row?(row, budget_month: budget_month)
          skipped_duplicates += 1
          next
        end

        budget_month.expense_entries.create!(
          occurred_on: row[:occurred_on],
          section: row[:section],
          category: row[:category],
          payee: row[:payee],
          planned_amount: row[:planned_amount],
          actual_amount: row[:actual_amount],
          account: row[:account],
          source_account: account_named(row[:source_account_name]),
          destination_account: account_named(row[:destination_account_name]),
          status: row[:status],
          need_or_want: row[:need_or_want],
          notes: row[:notes],
          source_file: row[:source_file]
        )
        created_entries += 1
      end

      { months: months_touched.size, entries: created_entries, duplicates: skipped_duplicates }
    end

    def import_summary_rows(rows)
      months_touched = Set.new

      rows.each do |raw_row|
        row = raw_row.deep_symbolize_keys
        month_on = row[:month_on].to_date
        budget_month = find_or_build_month(month_on)
        budget_month.leftover = row[:leftover] if row.key?(:leftover)
        budget_month.save!
        months_touched << budget_month.id
      end

      { months: months_touched.size, entries: 0, duplicates: 0 }
    end

    def find_or_build_month(month_on)
      @user.budget_months.find_or_create_by!(month_on: month_on.beginning_of_month) do |month|
        month.label = month_on.strftime("%B %Y")
      end
    end

    def parse_transaction_month(value, row_number:, errors:)
      if value.blank?
        errors << "Row #{row_number}: Month is required."
        return nil
      end

      Date.strptime("#{value}-01", "%Y-%m-%d")
    rescue ArgumentError
      errors << "Row #{row_number}: Month must use YYYY-MM format."
      nil
    end

    def parse_summary_month(value, row_number:, errors:)
      if value.blank?
        errors << "Row #{row_number}: Month is required."
        return nil
      end

      Date.parse("1 #{value}")
    rescue ArgumentError
      errors << "Row #{row_number}: Month could not be parsed."
      nil
    end

    def parse_date(value, row_number:, column:, errors:)
      text = value.to_s.strip
      return nil if text.blank?

      Date.parse(text)
    rescue ArgumentError
      errors << "Row #{row_number}: #{column} could not be parsed."
      nil
    end

    def parse_amount(value, row_number:, column:, errors:)
      text = value.to_s.gsub(/[,$]/, "").strip
      return nil if text.blank?

      BigDecimal(text)
    rescue ArgumentError
      errors << "Row #{row_number}: #{column} could not be parsed."
      nil
    end

    def normalize_section(section, row_number:, warnings:)
      key = section.to_s.downcase.strip
      return "income" if key == "income"
      return "fixed" if key == "fixed"
      return "variable" if key == "variable"
      return "debt" if key == "debt"
      return "manual" if key == "manual"
      return "auto" if key == "auto"

      warnings << "Row #{row_number}: Section #{section.to_s.presence || 'blank'} is not recognized and will be imported as Other."
      "other"
    end

    def normalize_status(status, row_number:, warnings:)
      key = status.to_s.downcase.strip
      return "paid" if key == "paid"
      return "skipped" if key == "skipped"
      return "planned" if key.blank? || key == "planned"

      warnings << "Row #{row_number}: Status #{status} is not recognized and will be imported as Planned."
      "planned"
    end

    def account_column_value(row, headers)
      headers.each do |header|
        next unless row.headers.include?(header)

        value = row[header].to_s.strip
        return value if value.present?
      end

      nil
    end

    def warn_unresolved_account(warnings, row_number, account_name, label:, fallback:)
      return if account_name.blank?
      return if account_named(account_name).present?

      warnings << "Row #{row_number}: #{label} #{account_name} does not match a saved account and will be #{fallback}."
    end

    def duplicate_transaction_row?(row, budget_month: nil)
      return false if row[:month_on].blank?

      budget_month ||= user.budget_months.find_by(month_on: row[:month_on].to_date.beginning_of_month)
      return false if budget_month.blank?

      budget_month.expense_entries.exists?(
        occurred_on: row[:occurred_on],
        section: row[:section],
        category: row[:category],
        payee: row[:payee],
        planned_amount: row[:planned_amount],
        actual_amount: row[:actual_amount],
        account: row[:account]
      )
    end

    def account_named(name)
      return if name.blank?

      account_by_name[name]
    end

    def account_by_name
      @account_by_name ||= user.accounts.index_by(&:name)
    end

    def failed_import_from(plan)
      message = Array(plan[:errors]).presence&.to_sentence || plan[:error].presence || "CSV import failed."
      { ok: false, error: message, warnings: Array(plan[:warnings]), errors: Array(plan[:errors]) }
    end

    def blank_row?(row)
      row.to_h.values.all? { |value| value.to_s.strip.blank? }
    end
  end
end
