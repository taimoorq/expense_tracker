module Platform
  module CanonicalJson
    module_function

    def dump(value)
      JSON.generate(normalize(value))
    end

    def normalize(value)
      case value
      when Hash
        value.deep_stringify_keys.sort.to_h.transform_values { |nested| normalize(nested) }
      when Array
        value.map { |nested| normalize(nested) }
      when Time, ActiveSupport::TimeWithZone, Date, DateTime
        value.iso8601
      when BigDecimal
        value.to_s("F")
      when Symbol
        value.to_s
      else
        value
      end
    end
  end
end
