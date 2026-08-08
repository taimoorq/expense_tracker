module Platform
  module ShadowReads
    class CloseReadinessComparison
      COMPARED_FIELDS = %i[unmatched_count unresolved_account_count].freeze

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
        target_readiness = Budgeting::CloseReadiness.call(period: period)
        target = {
          unmatched_count: target_readiness.unmatched_count,
          unresolved_account_count: target_readiness.unresolved_account_count
        }
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

      def legacy_result
        summary = Budgeting::LegacyPeriodSummary.call(budget_month: budget_month)
        {
          unmatched_count: summary.unmatched_count,
          unresolved_account_count: workspace.accounts.where(archived_at: nil).count do |account|
            !Accounts::BalanceResolver.new(account: account, as_of: period.starts_on.end_of_month).call.balance_available
          end
        }
      end

      def persist_result(result)
        discrepancy = workspace.migration_discrepancies.find_or_initialize_by(
          legacy_record_type: "BudgetMonth",
          legacy_record_id: budget_month.id,
          code: "shadow_close_readiness_mismatch"
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
