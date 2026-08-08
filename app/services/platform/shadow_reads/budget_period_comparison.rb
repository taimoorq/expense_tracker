module Platform
  module ShadowReads
    class BudgetPeriodComparison
      COMPARED_FIELDS = Budgeting::PeriodSummary::Result.members.freeze

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
        @persist = persist
      end

      def call
        legacy = Budgeting::LegacyPeriodSummary.call(budget_month: budget_month)
        target = Budgeting::PeriodSummary.call(period: period)
        mismatched_fields = COMPARED_FIELDS.reject { |field| legacy.public_send(field) == target.public_send(field) }
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

      attr_reader :budget_month, :period, :persist

      def persist_result(result)
        discrepancy = period.budget_workspace.migration_discrepancies.find_or_initialize_by(
          legacy_record_type: "BudgetMonth",
          legacy_record_id: budget_month.id,
          code: "shadow_budget_period_summary_mismatch"
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
