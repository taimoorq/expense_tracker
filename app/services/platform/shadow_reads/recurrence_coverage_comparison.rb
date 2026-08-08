module Platform
  module ShadowReads
    class RecurrenceCoverageComparison
      COMPARED_FIELDS = %i[
        occurrence_count
        missing_mapping_count
        missing_target_count
        wrong_period_count
        wrong_date_count
        wrong_template_count
        unmaterialized_count
        orphan_target_count
      ].freeze

      Result = Data.define(:budget_month, :period, :legacy, :target, :mismatched_fields) do
        def matched?
          mismatched_fields.empty?
        end

        def as_json(*)
          {
            budget_month_id: budget_month.id,
            budget_period_id: period.id,
            matched: matched?,
            mismatched_fields: mismatched_fields
          }
        end
      end

      def self.call(budget_month:, period:, persist: true)
        new(budget_month: budget_month, period: period, persist: persist).call
      end

      def initialize(budget_month:, period:, persist:)
        @budget_month = budget_month
        @period = period
        @workspace = period.budget_workspace
        @persist = persist
      end

      def call
        legacy = legacy_result
        target = target_result
        mismatched_fields = COMPARED_FIELDS.reject { |field| legacy.fetch(field) == target.fetch(field) }
        result = Result.new(
          budget_month: budget_month,
          period: period,
          legacy: legacy,
          target: target,
          mismatched_fields: mismatched_fields
        )
        persist_result(result) if persist
        result
      end

      private

      attr_reader :budget_month, :period, :persist, :workspace

      def entries
        @entries ||= budget_month.expense_entries
          .where.not(source_template_id: nil)
          .where.not(generated_entry_key: nil)
          .includes(:source_template)
          .to_a
      end

      def occurrence_mappings
        @occurrence_mappings ||= workspace.legacy_record_mappings.where(
          legacy_record_type: "ExpenseEntry",
          legacy_record_id: entries.map(&:id),
          target_record_type: "RecurringOccurrence"
        ).pluck(:legacy_record_id, :target_record_id).to_h
      end

      def occurrences
        @occurrences ||= RecurringOccurrence.where(id: occurrence_mappings.values).index_by(&:id)
      end

      def period_occurrences
        @period_occurrences ||= period.recurring_occurrences.to_a
      end

      def template_target_ids
        @template_target_ids ||= begin
          keys = entries.filter_map do |entry|
            [ entry.source_template_type, entry.source_template_id ] if entry.source_template.present?
          end.to_set
          workspace.legacy_record_mappings
            .where(target_record_type: "PlanningTemplate")
            .pluck(:legacy_record_type, :legacy_record_id, :target_record_id)
            .each_with_object({}) do |(type, id, target_id), result|
              result[[ type, id ]] = target_id if keys.include?([ type, id ])
            end
        end
      end

      def legacy_result
        zero_result.merge(
          occurrence_count: entries.size,
          orphan_target_count: 0
        )
      end

      def target_result
        values = zero_result.merge(occurrence_count: period_occurrences.size)
        entries.each do |entry|
          target_id = occurrence_mappings[entry.id]
          if target_id.blank?
            values[:missing_mapping_count] += 1
            next
          end
          occurrence = occurrences[target_id]
          if occurrence.blank?
            values[:missing_target_count] += 1
            next
          end

          values[:wrong_period_count] += 1 if occurrence.budget_period_id != period.id
          values[:wrong_date_count] += 1 if occurrence.scheduled_on != entry.occurred_on
          expected_template_id = template_target_ids[[ entry.source_template_type, entry.source_template_id ]]
          values[:wrong_template_count] += 1 if expected_template_id.blank? || occurrence.planning_template_id != expected_template_id
          values[:unmaterialized_count] += 1 unless occurrence.state_materialized? && occurrence.budget_item_id.present?
        end
        values[:orphan_target_count] = period_occurrences.count { |occurrence| !occurrence_mappings.value?(occurrence.id) }
        values
      end

      def zero_result
        COMPARED_FIELDS.index_with { 0 }
      end

      def persist_result(result)
        discrepancy = workspace.migration_discrepancies.find_or_initialize_by(
          legacy_record_type: "BudgetMonth",
          legacy_record_id: budget_month.id,
          code: "shadow_recurrence_coverage_mismatch"
        )
        if result.matched?
          return if discrepancy.new_record?

          discrepancy.update!(status: "resolved", resolved_at: Time.current, redacted_details: {})
        else
          discrepancy.update!(
            status: "open",
            resolved_at: nil,
            redacted_details: { "mismatched_fields" => result.mismatched_fields.map(&:to_s) }
          )
        end
      end
    end
  end
end
