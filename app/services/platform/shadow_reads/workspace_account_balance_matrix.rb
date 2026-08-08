module Platform
  module ShadowReads
    class WorkspaceAccountBalanceMatrix
      MAX_DATES_PER_ACCOUNT = 100

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

      def self.call(workspace:, as_of: Date.current, persist: true)
        new(workspace: workspace, as_of: as_of, persist: persist).call
      end

      def initialize(workspace:, as_of:, persist:)
        @workspace = workspace
        @as_of = as_of.to_date
        @persist = persist
      end

      def call
        comparisons = workspace.accounts.active_first.flat_map do |account|
          comparison_dates(account).map do |date|
            AccountBalanceComparison.call(account: account, as_of: date, persist: persist && date == as_of)
          end
        end
        Result.new(workspace: workspace, comparisons: comparisons)
      end

      private

      attr_reader :as_of, :persist, :workspace

      def comparison_dates(account)
        dates = [ as_of ]
        dates.concat(account.balance_observations.where(effective_through_at: ..as_of.end_of_day).pluck(:effective_through_at).map(&:to_date))
        dates.concat(account.account_activity_imports.where.not(started_on: nil).pluck(:started_on, :ended_on).flatten.compact)
        dates.concat(workspace.budget_periods.where(starts_on: ..as_of).pluck(:starts_on).map(&:end_of_month))
        dates.select { |date| date <= as_of }.uniq.sort.last(MAX_DATES_PER_ACCOUNT)
      end
    end
  end
end
