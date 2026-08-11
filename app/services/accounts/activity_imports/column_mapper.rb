module Accounts
  module ActivityImports
    class ColumnMapper
      REQUIRED_FIELDS = %i[transaction_on description].freeze
      HEADER_ALIASES = {
        transaction_on: [ "transaction date", "trans. date", "date", "activity date" ],
        posted_on: [ "post date", "posted date", "posting date" ],
        description: [ "description", "payee", "merchant", "name" ],
        raw_amount: [ "amount", "transaction amount" ],
        debit_amount: [ "debit", "debits", "debit amount" ],
        credit_amount: [ "credit", "credits", "credit amount" ],
        category: [ "category" ],
        activity_type: [ "type", "transaction type", "debit/credit" ],
        memo: [ "memo", "notes" ]
      }.freeze

      Result = Data.define(:mapping, :missing_fields, :extra_headers)

      def self.call(headers)
        new(headers).call
      end

      def self.split_amount_mapping?(mapping)
        mapping.values_at(:debit_amount, :credit_amount).all?(&:present?)
      end

      def initialize(headers)
        @headers = Array(headers).map(&:to_s)
      end

      def call
        mapping = HEADER_ALIASES.each_with_object({}) do |(field, aliases), detected|
          header = headers.find { |candidate| aliases.include?(normalize(candidate)) }
          detected[field] = header if header.present?
        end

        missing_fields = REQUIRED_FIELDS - mapping.keys
        missing_fields << :raw_amount unless mapping[:raw_amount].present? || self.class.split_amount_mapping?(mapping)

        Result.new(
          mapping: mapping,
          missing_fields: missing_fields,
          extra_headers: headers - mapping.values
        )
      end

      private

      attr_reader :headers

      def normalize(value)
        value.to_s.downcase.strip
      end
    end
  end
end
