module Platform
  module ShadowReads
    class AttentionComparison
      COMPARED_FIELDS = %i[
        due_planned_count
        due_soon_count
        missing_details_count
        paid_missing_actual_count
        auto_completed_count
        review_attention_count
        manual_entries_count
        linked_entries_count
        linked_paid_entries_count
      ].freeze

      Result = Data.define(:budget_month, :period, :as_of, :legacy, :target, :mismatched_fields) do
        def matched?
          mismatched_fields.empty?
        end

        def as_json(*)
          {
            budget_month_id: budget_month.id,
            budget_period_id: period.id,
            as_of: as_of,
            matched: matched?,
            mismatched_fields: mismatched_fields
          }
        end
      end

      def self.call(budget_month:, period:, as_of: Date.current, persist: true)
        new(budget_month: budget_month, period: period, as_of: as_of, persist: persist).call
      end

      def initialize(budget_month:, period:, as_of:, persist:)
        @budget_month = budget_month
        @period = period
        @as_of = as_of.to_date
        @persist = persist
      end

      def call
        legacy = target_compatible_legacy_summary
        target = Overview::TargetReviewSummary.call(period: period, today: as_of)
        mismatched_fields = COMPARED_FIELDS.reject { |field| legacy.fetch(field) == target.fetch(field) }
        result = Result.new(
          budget_month: budget_month,
          period: period,
          as_of: as_of,
          legacy: legacy,
          target: target,
          mismatched_fields: mismatched_fields
        )
        persist_result(result) if persist
        result
      end

      private

      attr_reader :as_of, :budget_month, :period, :persist

      def target_compatible_legacy_summary
        entries = budget_month.expense_entries.to_a.reject(&:skipped?)
        legacy = Overview::ReviewSummary.new(entries: entries, today: as_of).call
        due_count = entries.count do |entry|
          entry.occurred_on.present? && entry.occurred_on <= as_of && remaining_amount(entry).positive?
        end
        due_soon_count = entries.count do |entry|
          entry.occurred_on.present? && entry.occurred_on > as_of && entry.occurred_on <= as_of + 7.days &&
            remaining_amount(entry).positive?
        end
        legacy.merge(
          due_planned_count: due_count,
          due_soon_count: due_soon_count,
          paid_missing_actual_count: 0,
          auto_completed_count: 0,
          review_attention_count: due_count + legacy.fetch(:missing_details_count)
        )
      end

      def remaining_amount(entry)
        [ entry.planned_amount.to_d - entry.actual_amount.to_d, 0.to_d ].max
      end

      def persist_result(result)
        discrepancy = period.budget_workspace.migration_discrepancies.find_or_initialize_by(
          legacy_record_type: "BudgetMonth",
          legacy_record_id: budget_month.id,
          code: "shadow_attention_summary_mismatch"
        )
        if result.matched?
          return if discrepancy.new_record?

          discrepancy.update!(
            status: "resolved",
            resolved_at: Time.current,
            redacted_details: { "last_compared_on" => as_of }
          )
        else
          discrepancy.update!(
            status: "open",
            resolved_at: nil,
            redacted_details: {
              "as_of" => as_of,
              "mismatched_fields" => result.mismatched_fields.map(&:to_s)
            }
          )
        end
      end
    end
  end
end
