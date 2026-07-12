module Accounts
  module ActivityImports
    class ColumnMapper
      REQUIRED_FIELDS = %i[transaction_on description raw_amount].freeze
      HEADER_ALIASES = {
        transaction_on: [ "transaction date", "trans. date", "date", "activity date" ],
        posted_on: [ "post date", "posted date", "posting date" ],
        description: [ "description", "payee", "merchant", "name" ],
        raw_amount: [ "amount", "transaction amount" ],
        category: [ "category" ],
        activity_type: [ "type", "transaction type", "debit/credit" ],
        memo: [ "memo", "notes" ]
      }.freeze

      Result = Data.define(:mapping, :missing_fields, :extra_headers)

      def self.call(headers)
        new(headers).call
      end

      def initialize(headers)
        @headers = Array(headers).map(&:to_s)
      end

      def call
        mapping = HEADER_ALIASES.each_with_object({}) do |(field, aliases), detected|
          header = headers.find { |candidate| aliases.include?(normalize(candidate)) }
          detected[field] = header if header.present?
        end

        Result.new(
          mapping: mapping,
          missing_fields: REQUIRED_FIELDS - mapping.keys,
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
