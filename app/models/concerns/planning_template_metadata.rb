module PlanningTemplateMetadata
  extend ActiveSupport::Concern

  included do
    class_attribute :template_type_key_value, instance_writer: false
    class_attribute :template_source_file_value, instance_writer: false
    class_attribute :template_param_key_value, instance_writer: false
    class_attribute :template_recurring_source_value, instance_writer: false, default: false
    class_attribute :template_wizard_sections_value, instance_writer: false, default: []
    class_attribute :template_permitted_attributes_value, instance_writer: false, default: []
  end

  class_methods do
    def planning_template_metadata(type_key:, source_file:, param_key:, recurring_source:, wizard_sections:, permitted_attributes:)
      self.template_type_key_value = type_key.to_sym
      self.template_source_file_value = source_file
      self.template_param_key_value = param_key.to_sym
      self.template_recurring_source_value = recurring_source
      self.template_wizard_sections_value = Array(wizard_sections).map(&:to_s).freeze
      self.template_permitted_attributes_value = permitted_attributes.freeze
    end

    def template_type_key
      template_type_key_value
    end

    def template_source_file
      template_source_file_value
    end

    def template_param_key
      template_param_key_value
    end

    def recurring_source?
      template_recurring_source_value
    end

    def template_wizard_sections
      template_wizard_sections_value
    end

    def template_permitted_attributes
      template_permitted_attributes_value
    end

    def template_metadata
      {
        type_key: template_type_key,
        model_name: name,
        model_class: self,
        source_file: template_source_file,
        param_key: template_param_key,
        recurring_source: recurring_source?,
        wizard_sections: template_wizard_sections,
        permitted_attributes: template_permitted_attributes
      }
    end
  end

  def template_metadata
    self.class.template_metadata
  end

  def template_source_file
    self.class.template_source_file
  end
end
