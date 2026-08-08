module Platform
  module ShadowReads
    class WorkspaceBudgetPeriodMatrix
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
        comparisons = workspace.legacy_owner_user.budget_months.order(:month_on).filter_map do |month|
          mapping = workspace.legacy_record_mappings.find_by(
            legacy_record_type: "BudgetMonth",
            legacy_record_id: month.id,
            target_record_type: "BudgetPeriod"
          )
          period = BudgetPeriod.find_by(id: mapping&.target_record_id)
          next if period.blank?

          BudgetPeriodComparison.call(budget_month: month, period: period, persist: persist)
        end
        Result.new(workspace: workspace, comparisons: comparisons)
      end
    end
  end
end
