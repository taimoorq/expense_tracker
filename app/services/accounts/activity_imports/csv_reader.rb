require "csv"

module Accounts
  module ActivityImports
    class CsvReader
      Result = Data.define(:ok, :headers, :header_row_number, :rows, :metadata, :error)
      Row = Data.define(:row_number, :attributes)
      BEST_BUY_HEADERS = [ "Date", "Amount", "Description", "Details" ].freeze
      BEST_BUY_SOURCE_FORMAT = "best_buy_citibank_headerless_tsv".freeze
      BEST_BUY_AMOUNT_PATTERN = /\A\$-?(?:\d{1,3}(?:,\d{3})*|\d+)\.\d{2}\z/
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
        col_sep = detected_col_sep
        header_index = find_header_index(col_sep)
        return headerless_best_buy_result if header_index.blank? && headerless_best_buy_rows.present?
        return failure("Could not find a supported account activity CSV header.") if header_index.blank?

        csv_text = lines.drop(header_index).join
        table = CSV.parse(csv_text, headers: true, liberal_parsing: true, col_sep: col_sep)
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

      def find_header_index(col_sep)
        lines.index do |line|
          parsed = CSV.parse_line(line, liberal_parsing: true, col_sep: col_sep)
          next false if parsed.blank?

          ColumnMapper.call(parsed).missing_fields.empty?
        rescue CSV::MalformedCSVError
          false
        end
      end

      def lines
        @lines ||= File.open(file.path, "r:bom|utf-8", &:read).lines
      end

      def detected_col_sep
        delimiter_counts = lines.first(20).each_with_object({ "\t" => 0, "," => 0 }) do |line, counts|
          counts.each_key { |delimiter| counts[delimiter] += line.count(delimiter) }
        end

        delimiter_counts["\t"] > delimiter_counts[","] ? "\t" : ","
      end

      def headerless_best_buy_result
        rows = headerless_best_buy_rows.each.with_index(1).map do |values, row_number|
          Row.new(row_number: row_number, attributes: BEST_BUY_HEADERS.zip(values).to_h)
        end

        Result.new(
          ok: true,
          headers: BEST_BUY_HEADERS,
          header_row_number: 1,
          rows: rows,
          metadata: {
            headerless: true,
            delimiter: "tab",
            source_format: BEST_BUY_SOURCE_FORMAT
          },
          error: nil
        )
      end

      def headerless_best_buy_rows
        return @headerless_best_buy_rows if defined?(@headerless_best_buy_rows)

        @headerless_best_buy_rows = parse_headerless_best_buy_rows
      end

      def parse_headerless_best_buy_rows
        return unless detected_col_sep == "\t"

        parsed_rows = lines.filter_map do |line|
          next if line.strip.blank?

          CSV.parse_line(line, liberal_parsing: true, col_sep: "\t")
        end
        return if parsed_rows.empty? || parsed_rows.any? { |values| !best_buy_row?(values) }

        parsed_rows
      rescue CSV::MalformedCSVError
        nil
      end

      def best_buy_row?(values)
        return false unless values.size == BEST_BUY_HEADERS.size
        return false unless best_buy_date?(values[0])
        return false unless values[1].to_s.strip.match?(BEST_BUY_AMOUNT_PATTERN)

        values.values_at(2, 3).all? { |value| value.to_s.strip.present? }
      end

      def best_buy_date?(value)
        text = value.to_s.strip
        return false unless text.match?(%r{\A\d{1,2}/\d{1,2}/\d{4}\z})

        Date.strptime(text, "%m/%d/%Y")
        true
      rescue Date::Error
        false
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
