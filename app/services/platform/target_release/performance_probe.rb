module Platform
  module TargetRelease
    class PerformanceProbe
      DEFAULT_SAMPLES = 3

      ProbeResult = Data.define(
        :name, :durations_ms, :p95_ms, :max_select_count, :latency_budget_ms,
        :select_budget, :passed
      ) do
        def passed?
          passed
        end

        def as_json(*)
          {
            name: name,
            samples: durations_ms.size,
            durations_ms: durations_ms,
            p95_ms: p95_ms,
            max_select_count: max_select_count,
            latency_budget_ms: latency_budget_ms,
            select_budget: select_budget,
            passed: passed?
          }
        end
      end

      Result = Data.define(:workspace, :dataset_counts, :probes) do
        def passed?
          probes.all?(&:passed?)
        end

        def as_json(*)
          {
            workspace_id: workspace.id,
            dataset_counts: dataset_counts,
            passed: passed?,
            probes: probes.map(&:as_json)
          }
        end
      end

      Probe = Data.define(:name, :latency_budget_ms, :select_budget, :callable)

      def self.call(workspace:, samples: DEFAULT_SAMPLES)
        new(workspace: workspace, samples: samples).call
      end

      def initialize(workspace:, samples:)
        @workspace = workspace
        @user = workspace.legacy_owner_user
        @samples = samples.to_i.clamp(1, 10)
      end

      def call
        raise ArgumentError, "target reads must be enabled for performance measurement" unless workspace.target_reads_enabled?
        raise ArgumentError, "the workspace must have a legacy owner" if user.blank?

        Result.new(
          workspace: workspace,
          dataset_counts: dataset_counts,
          probes: probes.map { |probe| measure(probe) }
        )
      end

      private

      attr_reader :samples, :user, :workspace

      def probes
        @probes ||= begin
          values = [
            Probe.new("home", 500, 50, -> { Overview::PageData.new(user: user, today: as_of).call }),
            Probe.new("reports", 250, 22, -> { Reports::OverviewQuery.call(user: user) }),
            Probe.new("accounts_summary", 250, 18, -> { Accounts::Summary.new(user: user, include_trend: true).call }),
            Probe.new("activity", 250, 15, -> { Activity::IndexQuery.call(user: user, view: "all") }),
            Probe.new("period_summaries", 150, 10, -> { Budgeting::PeriodSummaryBatch.call(periods: recent_periods) })
          ]
          if account.present?
            values << Probe.new(
              "account_detail",
              250,
              14,
              -> { Accounts::DetailPage.new(account: account.reload, as_of: as_of, range: "1y").call }
            )
          end
          if category.present?
            values << Probe.new(
              "report_sources",
              250,
              12,
              lambda {
                Reports::SourceDrilldown.call(
                  user: user,
                  category: category.name,
                  starts_on: as_of.beginning_of_year,
                  ends_on: as_of
                )
              }
            )
          end
          values
        end
      end

      def measure(probe)
        probe.callable.call
        measurements = Array.new(samples) { measure_once(probe.callable) }
        durations = measurements.map { |measurement| measurement.fetch(:duration_ms) }
        counts = measurements.map { |measurement| measurement.fetch(:select_count) }
        p95 = percentile(durations, 0.95)
        max_select_count = counts.max
        ProbeResult.new(
          name: probe.name,
          durations_ms: durations,
          p95_ms: p95,
          max_select_count: max_select_count,
          latency_budget_ms: probe.latency_budget_ms,
          select_budget: probe.select_budget,
          passed: p95 <= probe.latency_budget_ms && max_select_count <= probe.select_budget
        )
      end

      def measure_once(callable)
        select_count = 0
        subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
          select_count += 1 if counted_select?(payload)
        end
        ActiveRecord::Base.connection.clear_query_cache
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        callable.call
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
        { duration_ms: (duration * 1_000).round(2), select_count: select_count }
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
      end

      def counted_select?(payload)
        !payload[:cached] && payload[:name] != "SCHEMA" && payload[:sql].match?(/\A\s*(?:SELECT|WITH)\b/i)
      end

      def percentile(values, quantile)
        ordered = values.sort
        ordered[([ (ordered.size * quantile).ceil - 1, 0 ].max)]
      end

      def account
        @account ||= workspace.accounts.active_first.first
      end

      def category
        @category ||= workspace.categories.active.order(:display_order, :name).first
      end

      def recent_periods
        @recent_periods ||= workspace.budget_periods.order(starts_on: :desc).limit(12).to_a.reverse
      end

      def as_of
        @as_of ||= [ Date.current, workspace.budget_periods.maximum(:starts_on)&.end_of_month ].compact.max
      end

      def dataset_counts
        {
          accounts: workspace.accounts.count,
          periods: workspace.budget_periods.count,
          items: workspace.budget_items.count,
          transactions: workspace.financial_transactions.count,
          postings: workspace.account_postings.count,
          allocations: workspace.budget_allocations.count,
          observations: workspace.balance_observations.count
        }
      end
    end
  end
end
