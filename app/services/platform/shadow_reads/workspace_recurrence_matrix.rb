module Platform
  module ShadowReads
    class WorkspaceRecurrenceMatrix
      Result = Data.define(:workspace, :comparisons) do
        def matched?
          comparisons.all?(&:matched?)
        end

        def as_json(*)
          {
            workspace_id: workspace.id,
            matched: matched?,
            comparison_count: comparisons.size,
            mismatch_count: comparisons.count { |comparison| !comparison.matched? }
          }
        end
      end

      def self.call(workspace:, persist: true)
        mappings = workspace.legacy_record_mappings.where(
          legacy_record_type: "BudgetMonth",
          target_record_type: "BudgetPeriod"
        ).pluck(:legacy_record_id, :target_record_id).to_h
        periods = workspace.budget_periods.where(id: mappings.values).index_by(&:id)
        comparisons = workspace.legacy_owner_user.budget_months.order(:month_on).filter_map do |month|
          period = periods[mappings[month.id]]
          next if period.blank?

          RecurrenceCoverageComparison.call(budget_month: month, period: period, persist: persist)
        end
        Result.new(workspace: workspace, comparisons: comparisons)
      end
    end
  end
end
