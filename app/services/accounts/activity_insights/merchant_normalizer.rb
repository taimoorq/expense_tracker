require "cgi"

module Accounts
  module ActivityInsights
    class MerchantNormalizer
      PREFIX_PATTERN = /\A(?:TST\*|SQ\s*\*|DD\s*\*|GOOGLE\s*\*|WL\s*\*|NYX\*|SP\s+|SQSP\*\s*)/i
      LOCATION_PATTERN = /\s+\b[A-Z][A-Z\s.-]{2,}\s+[A-Z]{2}(?:\d{3,})?\z/
      REFERENCE_PATTERN = /(?:#?\d{5,}|(?=\b[A-Z0-9]{7,}\b)(?=\b[A-Z0-9]*\d)[A-Z0-9]+)/i

      def self.call(description)
        new(description).call
      end

      def initialize(description)
        @description = description.to_s
      end

      def call
        normalized = CGI.unescapeHTML(description)
          .squish
          .sub(PREFIX_PATTERN, "")
          .gsub(REFERENCE_PATTERN, "")
          .sub(LOCATION_PATTERN, "")
          .gsub(/\s+[-*]\s*\z/, "")
          .squish

        normalized.presence || description.squish
      end

      private

      attr_reader :description
    end
  end
end
