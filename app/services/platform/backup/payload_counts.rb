module Platform
  module Backup
    module PayloadCounts
      def self.call(data)
        data.each_with_object({}) do |(scope, value), counts|
          counts[scope.to_s] = count_records(value)
        end
      end

      def self.count_records(value)
        case value
        when Array then value.size
        when Hash then value.values.sum { |nested| count_records(nested) }
        else 0
        end
      end
      private_class_method :count_records
    end
  end
end
