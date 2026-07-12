require "digest"

module Accounts
  module ActivityImports
    class FingerprintBuilder
      def initialize
        @occurrences = Hash.new(0)
      end

      def call(row)
        base_key = [
          row[:transaction_on],
          row[:posted_on],
          normalize(row[:description]),
          normalize(row[:category]),
          normalize(row[:activity_type]),
          decimal_key(row[:raw_amount])
        ].join("|")
        @occurrences[base_key] += 1

        Digest::SHA256.hexdigest("#{base_key}|#{@occurrences[base_key]}")
      end

      private

      def normalize(value)
        value.to_s.downcase.squish
      end

      def decimal_key(value)
        value.to_d.to_s("F")
      end
    end
  end
end
