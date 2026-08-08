module Platform
  module TargetSync
    class PlanningTemplateWriter
      MAPPING_VERSION = "target-live-v1".freeze

      def self.call(source:, action: :upsert)
        new(source: source, action: action).call
      end

      def initialize(source:, action:)
        @source = source
        @action = action.to_sym
      end

      def call
        @context = Context.for(source)
        return if context.blank?
        raise ArgumentError, "Unsupported planning template sync action" unless action.in?(%i[upsert archive])

        Platform::Operations::Executor.call(
          workspace: workspace,
          actor_membership: membership,
          operation_type: "sync_legacy_planning_template",
          idempotency_key: "legacy:#{source.class.name}:#{source.id}:#{source.lock_version}:#{action}",
          request: source_attributes.merge("sync_action" => action),
          redacted_parameters: { "legacy_record_type" => source.class.name, "legacy_record_id" => source.id },
          on_replay: ->(reference) { ::PlanningTemplate.find(reference.fetch("id")) }
        ) do |operation|
          @mapping_store = TargetBackfill::MappingStore.new(
            workspace: workspace,
            operation_run: operation,
            version: MAPPING_VERSION
          )
          template = mapping_store.target_for(source: source, target_class: ::PlanningTemplate)
          raise MissingMapping, "The planning template has not been synchronized" if action == :archive && template.blank?

          created = template.blank?
          template ||= mapping_store.build_target(source: source, target_class: ::PlanningTemplate)
          template.assign_attributes(
            TargetTranslation::PlanningTemplate.attributes(
              source: source,
              workspace: workspace,
              archived_at: action == :archive ? Time.current : nil
            )
          )
          template.save!
          sync_detail(template) unless action == :archive
          mapping = mapping_store.record!(source: source, target: template, source_attributes: source_attributes)
          mapping.update!(status: "omitted", metadata: mapping.metadata.merge("archived_by_legacy_delete" => true)) if action == :archive
          Audit::Recorder.call(
            workspace: workspace,
            actor_membership: membership,
            operation_run: operation,
            entity: template,
            action: action == :archive ? "archive" : (created ? "create" : "edit"),
            changed_fields: template.previous_changes.keys - %w[created_at updated_at lock_version]
          )
          Platform::Operations::Executor::Completion.new(
            value: template,
            result_counts: { "planning_templates" => 1 },
            result_reference: { "type" => "PlanningTemplate", "id" => template.id }
          )
        end
      end

      private

      attr_reader :action, :context, :mapping_store, :source

      delegate :membership, :workspace, to: :context

      def sync_detail(template)
        if source.is_a?(CreditCard)
          sync_credit_card_policy(template)
        else
          sync_recurrence_rule(template)
          sync_payment_plan_term(template) if source.is_a?(PaymentPlan)
        end
      end

      def sync_recurrence_rule(template)
        rule = RecurrenceRule.find_or_initialize_by(planning_template: template)
        rule.assign_attributes(TargetTranslation::PlanningTemplate.recurrence_attributes(source))
        rule.save!
        allowed_months = TargetTranslation::PlanningTemplate.allowed_months(source)
        allowed_months.each { |month_number| rule.recurrence_months.find_or_create_by!(month_number: month_number) }
        rule.recurrence_months.where.not(month_number: allowed_months).delete_all
      end

      def sync_payment_plan_term(template)
        PaymentPlanTerm.find_or_initialize_by(planning_template: template).tap do |term|
          term.assign_attributes(TargetTranslation::PlanningTemplate.payment_plan_term_attributes(source))
          term.save!
        end
      end

      def sync_credit_card_policy(template)
        if source.linked_account.blank? || source.payment_account.blank?
          raise MissingAccount, "A credit card schedule requires both the card and payment accounts"
        end

        CreditCardPaymentPolicy.find_or_initialize_by(planning_template: template).tap do |policy|
          policy.assign_attributes(
            TargetTranslation::PlanningTemplate.credit_card_policy_attributes(source, workspace: workspace)
          )
          policy.save!
        end
      end

      def source_attributes
        @source_attributes ||= source.attributes.except("created_at", "updated_at")
      end

      class MissingAccount < WriteRejected; end
      class MissingMapping < WriteRejected; end
    end
  end
end
