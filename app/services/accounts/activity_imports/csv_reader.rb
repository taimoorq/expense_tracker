require "csv"

module Accounts
  module ActivityImports
    class CsvReader
      Result = Data.define(:ok, :headers, :header_row_number, :rows, :metadata, :error)
      Row = Data.define(:row_number, :attributes)
      BALANCE_PATTERN = /
        (?<label>(?:account|current|beginning|ending)\s+balance)
        (?:\s+as\s+of\s+(?<date>(?:[A-Za-z]+\s+\d{1,2},?\s+\d{4})|(?:\d{1,2}\/\d{1,2}\/\d{2,4})))?
        [\s,:]*
        \$?(?<amount>\(?-?[\d,]+(?:\.\d{2})?\)?)
      /ix

      def initialize(file:)
        @file = file
      end

      def call
        header_index = find_header_index
        return failure("Could not find a supported account activity CSV header.") if header_index.blank?

        csv_text = lines.drop(header_index).join
        table = CSV.parse(csv_text, headers: true, liberal_parsing: true)
        rows = table.each.with_index(header_index + 2).filter_map do |row, row_number|
          next if blank_row?(row)

          Row.new(row_number: row_number, attributes: row.to_h)
        end

        Result.new(ok: true, headers: table.headers, header_row_number: header_index + 1, rows: rows, metadata: metadata_for(header_index), error: nil)
      rescue CSV::MalformedCSVError => error
        failure("CSV could not be parsed: #{error.message}")
      rescue => error
        failure(error.message)
      end

      private

      attr_reader :file

      def find_header_index
        lines.index do |line|
          parsed = CSV.parse_line(line, liberal_parsing: true)
          next false if parsed.blank?

          ColumnMapper.call(parsed).missing_fields.empty?
        rescue CSV::MalformedCSVError
          false
        end
      end

      def lines
        @lines ||= File.readlines(file.path)
      end

      def blank_row?(row)
        row.to_h.values.all? { |value| value.to_s.strip.blank? }
      end

      def metadata_for(header_index)
        preamble = lines.take(header_index).map(&:strip).reject(&:blank?)
        balance = extract_balance(preamble)

        {
          institution_name: preamble.first,
          institution_balance: balance&.fetch(:amount),
          institution_balance_as_of: balance&.fetch(:as_of)&.to_s,
          institution_balance_label: balance&.fetch(:label),
          preamble_lines: preamble
        }.compact
      end

      def extract_balance(preamble)
        balances = preamble.filter_map do |line|
          match = line.match(BALANCE_PATTERN)
          next if match.blank?

          amount = parse_amount(match[:amount])
          next if amount.blank?

          {
            label: match[:label].to_s.squish,
            amount: amount.to_s("F"),
            as_of: parse_date(match[:date])
          }.compact
        end

        balances.find { |balance| balance[:label].match?(/\A(?:ending|current|account)/i) } || balances.first
      end

      def parse_amount(value)
        text = value.to_s.strip
        negative = text.start_with?("(") && text.end_with?(")")
        text = text.delete("(),$")
        amount = BigDecimal(text)
        negative ? -amount : amount
      rescue ArgumentError
        nil
      end

      def parse_date(value)
        return if value.blank?

        text = value.to_s.strip
        return Date.strptime(text, "%m/%d/%Y") if text.match?(%r{\A\d{1,2}/\d{1,2}/\d{4}\z})
        return Date.strptime(text, "%m/%d/%y") if text.match?(%r{\A\d{1,2}/\d{1,2}/\d{2}\z})

        Date.parse(text)
      rescue ArgumentError
        nil
      end

      def failure(message)
        Result.new(ok: false, headers: [], header_row_number: nil, rows: [], metadata: {}, error: message)
      end
    end
  end
end
