module Accounts
  module ActivityImports
    class AmountNormalizer
      STRATEGIES = AccountActivityImport::AMOUNT_STRATEGIES
      DEBIT_TYPES = %w[charge debit fee purchase sale withdrawal].freeze
      CREDIT_TYPES = %w[adjustment credit deposit payment refund return].freeze

      Result = Data.define(:raw_amount, :amount, :account_delta)

      def self.infer_strategy(rows:, mapping:)
        type_header = direction_header(rows: rows, mapping: mapping)
        if type_header.present? && rows.any? { |row| typed_direction(row.attributes[type_header]).present? }
          return "type_column"
        end

        amounts = rows.filter_map { |row| parse_amount(row.attributes[mapping[:raw_amount]]) }
        positive_count = amounts.count(&:positive?)
        negative_count = amounts.count(&:negative?)

        positive_count >= negative_count ? "charges_are_positive" : "charges_are_negative"
      end

      def self.direction_header(rows:, mapping:)
        activity_type_header = mapping[:activity_type]
        return activity_type_header if activity_type_header.present? && rows.any? { |row| typed_direction(row.attributes[activity_type_header]).present? }

        category_header = mapping[:category]
        return unless category_header.present?

        typed_rows = rows.filter_map { |row| row.attributes[category_header].presence }
        return if typed_rows.empty?
        return unless typed_rows.all? { |value| typed_direction(value).present? }

        category_header
      end

      def self.normalize(raw_amount:, activity_type:, strategy:)
        new(raw_amount: raw_amount, activity_type: activity_type, strategy: strategy).call
      end

      def self.typed_direction(value)
        tokens = value.to_s.downcase.scan(/[a-z]+/)
        return :debit if (tokens & DEBIT_TYPES).any?
        return :credit if (tokens & CREDIT_TYPES).any?

        nil
      end

      def self.parse_amount(value)
        text = value.to_s.gsub(/[,$]/, "").strip
        return nil if text.blank?

        BigDecimal(text)
      rescue ArgumentError
        nil
      end

      def initialize(raw_amount:, activity_type:, strategy:)
        @raw_amount = self.class.parse_amount(raw_amount)
        @activity_type = activity_type
        @strategy = strategy.to_s
      end

      def call
        raise ArgumentError, "Amount could not be parsed." if raw_amount.blank?
        raise ArgumentError, "Amount strategy is not supported." unless strategy.in?(STRATEGIES)

        amount = raw_amount.abs
        Result.new(raw_amount: raw_amount, amount: amount, account_delta: normalized_delta(amount))
      end

      private

      attr_reader :raw_amount, :activity_type, :strategy

      def normalized_delta(amount)
        case strategy
        when "charges_are_positive"
          raw_amount.positive? ? -amount : amount
        when "charges_are_negative"
          raw_amount.negative? ? -amount : amount
        when "type_column"
          direction = self.class.typed_direction(activity_type)
          return -amount if direction == :debit
          return amount if direction == :credit

          raw_amount.negative? ? -amount : amount
        end
      end
    end
  end
end
