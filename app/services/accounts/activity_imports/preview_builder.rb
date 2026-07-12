require "set"

module Accounts
  module ActivityImports
    class PreviewBuilder
      SAMPLE_LIMIT = 10

      def initialize(user:, account:, file:)
        @user = user
        @account = account
        @file = file
      end

      def call
        reader_result = CsvReader.new(file: file).call
        return failed(reader_result.error) unless reader_result.ok

        mapping_result = ColumnMapper.call(reader_result.headers)
        return failed("Missing required columns: #{mapping_result.missing_fields.map(&:to_s).to_sentence}.") if mapping_result.missing_fields.any?

        amount_strategy = AmountNormalizer.infer_strategy(rows: reader_result.rows, mapping: mapping_result.mapping)
        direction_header = AmountNormalizer.direction_header(rows: reader_result.rows, mapping: mapping_result.mapping)
        parsed_rows = parse_rows(reader_result.rows, mapping_result.mapping, amount_strategy, direction_header)
        duplicate_count = parsed_rows.count { |row| row[:duplicate] }
        importable_count = parsed_rows.count { |row| row[:importable] }
        institution_balance = normalize_institution_balance(reader_result.metadata[:institution_balance])
        institution_balance_as_of = reader_result.metadata[:institution_balance_as_of].presence

        {
          ok: row_errors.empty?,
          account_id: account.id,
          original_filename: file.original_filename,
          header_row_number: reader_result.header_row_number,
          headers: reader_result.headers,
          column_mapping: mapping_result.mapping,
          amount_strategy: amount_strategy,
          rows_count: parsed_rows.size,
          imported_count: importable_count,
          duplicate_count: duplicate_count,
          started_on: parsed_rows.filter_map { |row| row[:transaction_on] }.min,
          ended_on: parsed_rows.filter_map { |row| row[:transaction_on] }.max,
          institution_balance: institution_balance&.to_s("F"),
          institution_balance_as_of: institution_balance_as_of,
          institution_name: reader_result.metadata[:institution_name],
          warnings: warnings,
          errors: row_errors,
          metadata: import_metadata(reader_result.metadata, institution_balance, institution_balance_as_of),
          rows: parsed_rows,
          sample_rows: parsed_rows.first(SAMPLE_LIMIT)
        }
      end

      private

      attr_reader :account, :file, :user

      def parse_rows(rows, mapping, amount_strategy, direction_header)
        fingerprint_builder = FingerprintBuilder.new
        existing_fingerprints = account.account_activities.pluck(:fingerprint).to_set

        rows.filter_map do |row|
          normalized = normalize_row(row, mapping, amount_strategy, direction_header)
          next if normalized.blank?

          fingerprint = fingerprint_builder.call(normalized)
          duplicate = existing_fingerprints.include?(fingerprint)
          normalized.merge(
            fingerprint: fingerprint,
            duplicate: duplicate,
            importable: !duplicate
          )
        end
      end

      def normalize_row(row, mapping, amount_strategy, direction_header)
        row_errors = []
        attributes = row.attributes
        return nil if attributes[mapping[:raw_amount]].to_s.strip.blank?

        transaction_on = parse_date(attributes[mapping[:transaction_on]], row_number: row.row_number, column: mapping[:transaction_on], errors: row_errors)
        posted_on = parse_date(attributes[mapping[:posted_on]], row_number: row.row_number, column: mapping[:posted_on], errors: row_errors) if mapping[:posted_on].present?
        normalized_amount = normalize_amount(attributes, mapping, amount_strategy, direction_header, row.row_number, row_errors)
        description = attributes[mapping[:description]].to_s.strip
        row_errors << "Row #{row.row_number}: Description is required." if description.blank?

        if row_errors.any?
          row_errors.each { |error| self.row_errors << error }
          return nil
        end

        {
          row_number: row.row_number,
          transaction_on: transaction_on,
          posted_on: posted_on,
          description: description,
          category: value_for(attributes, mapping[:category]),
          activity_type: value_for(attributes, mapping[:activity_type]) || activity_type_from_direction_header(attributes, mapping, direction_header),
          memo: value_for(attributes, mapping[:memo]),
          raw_amount: normalized_amount.raw_amount.to_s("F"),
          amount: normalized_amount.amount.to_s("F"),
          account_delta: normalized_amount.account_delta.to_s("F"),
          raw_payload: attributes
        }
      end

      def normalize_amount(attributes, mapping, amount_strategy, direction_header, row_number, errors)
        AmountNormalizer.normalize(
          raw_amount: attributes[mapping[:raw_amount]],
          activity_type: attributes[direction_header],
          strategy: amount_strategy
        )
      rescue ArgumentError => error
        errors << "Row #{row_number}: #{error.message}"
        nil
      end

      def parse_date(value, row_number:, column:, errors:)
        text = value.to_s.strip
        if text.blank?
          errors << "Row #{row_number}: #{column} is required."
          return nil
        end

        begin
          Date.strptime(text, "%m/%d/%Y")
        rescue ArgumentError
          Date.parse(text)
        end
      rescue ArgumentError
        errors << "Row #{row_number}: #{column} could not be parsed."
        nil
      end

      def value_for(attributes, header)
        return if header.blank?

        attributes[header].to_s.strip.presence
      end

      def normalize_institution_balance(value)
        return if value.blank?

        amount = BigDecimal(value.to_s)
        return -amount.abs if account.liability? && amount.positive?

        amount
      rescue ArgumentError
        nil
      end

      def import_metadata(reader_metadata, institution_balance, institution_balance_as_of)
        metadata = reader_metadata.to_h.stringify_keys.compact
        metadata["institution_balance"] = institution_balance.to_s("F") if institution_balance.present?
        metadata["institution_balance_as_of"] = institution_balance_as_of if institution_balance_as_of.present?
        metadata
      end

      def activity_type_from_direction_header(attributes, mapping, direction_header)
        return if direction_header.blank? || direction_header != mapping[:category]

        value_for(attributes, direction_header)
      end

      def warnings
        @warnings ||= []
      end

      def row_errors
        @row_errors ||= []
      end

      def failed(error)
        {
          ok: false,
          account_id: account.id,
          original_filename: file&.original_filename,
          rows_count: 0,
          imported_count: 0,
          duplicate_count: 0,
          warnings: [],
          errors: [ error ],
          metadata: {},
          rows: [],
          sample_rows: []
        }
      end
    end
  end
end
