module BankConnections
  module Simplefin
    class Normalizer
      class Invalid < StandardError; end

      def self.text(value, required: false)
        raise Invalid, "A required text field is missing." if required && (!value.is_a?(String) || value.blank?)
        raise Invalid, "An invalid text field was returned." unless value.nil? || value.is_a?(String)
        value.to_s.tr("\u0000", "").first(500)
      end

      def self.identity(value)
        raise Invalid, "A provider identity is missing or too long." unless value.is_a?(String) && value.present? && value.bytesize <= 500 && !value.include?("\u0000")
        value
      end

      def self.money(value, optional: false)
        return if optional && value.nil?
        raise Invalid, "A balance or amount is not a decimal string." unless value.is_a?(String) && value.match?(/\A-?\d+(?:\.\d{1,4})?\z/)
        amount = BigDecimal(value)
        raise Invalid, "An amount is outside the supported range." unless amount.finite? && amount.abs < 10**15
        amount
      end

      def self.time(value, fetched_at:, optional: false)
        return if optional && (value.nil? || value == 0)
        raise Invalid, "A source timestamp is missing or invalid." unless value.is_a?(Integer) && value.positive?
        instant = Time.at(value).utc
        raise Invalid, "A source timestamp is outside the supported range." unless instant >= Time.utc(1970) && instant <= fetched_at
        instant
      end

      def self.errors(payload)
        structured = Array(payload["errlist"]).filter_map do |error|
          next unless error.is_a?(Hash)
          { "code" => safe_message(error["code"]), "message" => safe_message(error["msg"]),
            "connection_id" => error["conn_id"].to_s.first(500), "account_id" => error["account_id"].to_s.first(500) }
        end
        structured + Array(payload["errors"]).map { |message| { "code" => "provider", "message" => safe_message(message) } }
      end

      def self.safe_message(value)
        ActionController::Base.helpers.strip_tags(value.to_s).gsub(%r{https?://\S+}, "[provider link]").gsub(/(?:Basic|Bearer)\s+\S+/i, "[redacted]").tr("\u0000", "").first(500)
      end
    end
  end
end
