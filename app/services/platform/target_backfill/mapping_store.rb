require "digest"

module Platform
  module TargetBackfill
    class MappingStore
      def initialize(workspace:, operation_run:, version: WorkspaceBootstrap::VERSION)
        @workspace = workspace
        @operation_run = operation_run
        @version = version
      end

      def target_for(source:, target_class:)
        mapping = mapping_for(source: source, target_type: target_class.name)
        return if mapping.blank?

        target = target_class.find_by(id: mapping.target_record_id)
        return target if target.present?

        record_discrepancy!(source: source, code: "missing_mapped_target", details: { target_type: target_class.name })
        nil
      end

      def record!(source:, target:, source_attributes:, metadata: {})
        checksum = Digest::SHA256.hexdigest(Platform::CanonicalJson.dump(source_attributes))
        mapping = mapping_for(source: source, target_type: target.class.name) || LegacyRecordMapping.new(
          budget_workspace: workspace,
          legacy_record_type: source.class.name,
          legacy_record_id: source.id,
          target_record_type: target.class.name
        )

        if mapping.persisted? && mapping.target_record_id != target.id
          record_discrepancy!(source: source, code: "mapping_target_changed", details: { target_type: target.class.name })
          raise MappingConflict, "#{source.class.name} #{source.id} already maps to another #{target.class.name}"
        end

        mapping.assign_attributes(
          target_record_id: target.id,
          mapping_version: version,
          source_checksum: checksum,
          status: "mapped",
          metadata: metadata
        )
        mapping.save!
        mapping
      end

      def record_discrepancy!(source:, code:, details: {})
        discrepancy = MigrationDiscrepancy.find_or_initialize_by(
          budget_workspace: workspace,
          legacy_record_type: source.class.name,
          legacy_record_id: source.id,
          code: code
        )
        discrepancy.operation_run = operation_run
        discrepancy.status = "open"
        discrepancy.redacted_details = details
        discrepancy.resolved_at = nil
        discrepancy.save!
        discrepancy
      end

      def build_target(source:, target_class:, attributes: {})
        target_id = if target_class.exists?(id: source.id)
          record_discrepancy!(source: source, code: "#{target_class.name.underscore}_id_collision")
          SecureRandom.uuid
        else
          source.id
        end
        target_class.new(attributes.merge(id: target_id))
      end

      private

      attr_reader :operation_run, :version, :workspace

      def mapping_for(source:, target_type:)
        LegacyRecordMapping.find_by(
          budget_workspace: workspace,
          legacy_record_type: source.class.name,
          legacy_record_id: source.id,
          target_record_type: target_type
        )
      end

      class MappingConflict < StandardError; end
    end
  end
end
