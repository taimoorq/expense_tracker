module Accounts
  module ActivityInsights
    class Classifier
      INTEREST_PATTERN = /\b(?:interest|finance charge|apr charge)\b/i
      FEE_PATTERN = /\b(?:fee|fees|service charge|overdraft|late charge|returned payment)\b/i
      PAYMENT_PATTERN = /\b(?:payment|thank you|autopay)\b/i
      REFUND_PATTERN = /\b(?:refund|return|credit|adjustment)\b/i

      def self.call(activity)
        new(activity).call
      end

      def initialize(activity)
        @activity = activity
      end

      def call
        return :interest if charge? && interest?
        return :fee if charge? && fee?
        return :payment if credit? && payment?
        return :credit if credit? && refund?
        return :credit if credit?
        return :charge if charge?

        :neutral
      end

      private

      attr_reader :activity

      def charge?
        activity.account_delta.to_d.negative?
      end

      def credit?
        activity.account_delta.to_d.positive?
      end

      def interest?
        searchable.match?(INTEREST_PATTERN)
      end

      def fee?
        searchable.match?(FEE_PATTERN)
      end

      def payment?
        searchable.match?(PAYMENT_PATTERN)
      end

      def refund?
        searchable.match?(REFUND_PATTERN)
      end

      def searchable
        @searchable ||= [
          activity.description,
          activity.category,
          activity.activity_type,
          activity.memo
        ].compact.join(" ")
      end
    end
  end
end
