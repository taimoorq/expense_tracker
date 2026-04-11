module Recurring
  class TemplateCatalog
    TEMPLATE_MODEL_NAMES = %w[PaySchedule Subscription MonthlyBill PaymentPlan CreditCard].freeze

    class << self
      def models
        @models ||= TEMPLATE_MODEL_NAMES.filter_map do |model_name|
          model_name.safe_constantize
        end.select { |klass| klass.respond_to?(:template_metadata) }
      end

      def recurring_models
        models.select(&:recurring_source?)
      end

      def wizard_models
        models.select { |klass| klass.template_wizard_sections.any? }
      end

      def recurring_source_files
        recurring_models.map(&:template_source_file)
      end

      def wizard_template_types
        wizard_models.map { |klass| klass.template_type_key.to_s }
      end

      def model_for_template_type(template_type)
        models.find { |klass| klass.template_type_key.to_s == template_type.to_s }
      end

      def model_for_source_file(source_file)
        models.find { |klass| klass.template_source_file == source_file.to_s }
      end

      def model_for(record_or_type)
        return nil if record_or_type.blank?
        return record_or_type if record_or_type.is_a?(Class) && record_or_type.respond_to?(:template_metadata)
        return record_or_type.class if record_or_type.respond_to?(:template_metadata)

        models.find do |klass|
          record_or_type.to_s == klass.name || record_or_type.to_s == klass.template_type_key.to_s
        end
      end

      def definition_for(record_or_type)
        model_for(record_or_type)&.template_metadata
      end

      def definition_for_source_file(source_file)
        model_for_source_file(source_file)&.template_metadata
      end

      def user_record_from_token(user:, token:)
        model_name, record_id = token.to_s.split(":", 2)
        return nil if model_name.blank? || record_id.blank?

        klass = model_for(model_name)
        return nil if klass.blank?

        scope = user.public_send(klass.model_name.route_key)
        scope = scope.active_only if scope.respond_to?(:active_only)
        scope.find_by(id: record_id)
      end
    end
  end
end
