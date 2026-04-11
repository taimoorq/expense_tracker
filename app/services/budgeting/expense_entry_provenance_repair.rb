module Budgeting
  class ExpenseEntryProvenanceRepair
    def self.relink_for(user)
      user.expense_entries.find_each do |entry|
        new(entry: entry).repair!
      end
    end

    def initialize(entry:, source_template_type: nil, source_template_name: nil)
      @entry = entry
      @source_template_type = source_template_type.presence
      @source_template_name = source_template_name.presence
    end

    def repair!
      relink_source_template
      entry.valid?
      return unless entry.changed?

      entry.save!
    end

    private

    attr_reader :entry, :source_template_type, :source_template_name

    def relink_source_template
      return if entry.source_template.present?

      template_record = explicit_template_record || inferred_template_record
      entry.source_template = template_record if template_record.present?
    end

    def explicit_template_record
      return if source_template_type.blank?

      allowed_model_names = Recurring::TemplateCatalog.models.map(&:name)
      return unless allowed_model_names.include?(source_template_type)

      source_template_type.constantize.where(user_id: entry.user_id).find_by(name: template_lookup_name)
    rescue NameError
      nil
    end

    def inferred_template_record
      definition = entry.source_definition
      return if definition.blank?

      definition.fetch(:model_name).constantize.where(user_id: entry.user_id).find_by(name: template_lookup_name)
    rescue NameError
      nil
    end

    def template_lookup_name
      source_template_name || entry.payee
    end
  end
end
