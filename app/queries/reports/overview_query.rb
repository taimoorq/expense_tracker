module Reports
  class OverviewQuery
    PeriodRow = Data.define(
      :month, :summary, :source_label, :calculation_version, :closed_at, :source_path, :close_id
    )
    CategoryRow = Data.define(:label, :value, :source_path)
    Result = Data.define(
      :period_rows,
      :labels,
      :planned_outflow,
      :actual_outflow,
      :category_rows,
      :category_labels,
      :category_values,
      :account_summary,
      :calculation_version
    )

    def self.call(user:)
      new(user: user).call
    end

    def initialize(user:)
      @user = user
    end

    def call
      rows = period_rows
      categories = category_totals.first(8).map do |label, value|
        CategoryRow.new(
          label: label,
          value: value,
          source_path: routes.report_sources_path(
            category: label,
            starts_on: period_date_range.begin,
            ends_on: period_date_range.end
          )
        )
      end
      Result.new(
        period_rows: rows,
        labels: rows.map { |row| row.month.month_on.strftime("%b %Y") },
        planned_outflow: rows.map { |row| row.summary.planned_outflow.to_f },
        actual_outflow: rows.map { |row| row.summary.actual_outflow.to_f },
        category_rows: categories,
        category_labels: categories.map(&:label),
        category_values: categories.map { |row| row.value.to_f },
        account_summary: Accounts::Summary.new(user: user, include_trend: true).call,
        calculation_version: target_reads? ? "target-v1" : "legacy-compatible-v1"
      )
    end

    private

    attr_reader :user

    def period_rows
      @period_rows ||= period_rows_months.map do |month|
        if target_reads?
          period = mapped_periods_by_month_id.fetch(month.id)
          close = active_closes_by_period_id[period.id]
          if close
            PeriodRow.new(
              month: month,
              summary: close.report_summary,
              source_label: "Closed snapshot",
              calculation_version: close.calculation_version,
              closed_at: close.closed_at,
              source_path: routes.budget_month_month_close_path(month),
              close_id: close.id
            )
          else
            PeriodRow.new(
              month: month,
              summary: live_target_summaries.fetch(period),
              source_label: "Live target data",
              calculation_version: Budgeting::PeriodSummary::CALCULATION_VERSION,
              closed_at: nil,
              source_path: routes.budget_month_path(month),
              close_id: nil
            )
          end
        else
          PeriodRow.new(
            month: month,
            summary: Budgeting::LegacyPeriodSummary.call(budget_month: month),
            source_label: "Live legacy data",
            calculation_version: "legacy-compatible-v1",
            closed_at: nil,
            source_path: routes.budget_month_path(month),
            close_id: nil
          )
        end
      end
    end

    def category_totals
      return target_category_totals if target_reads?

      totals = Hash.new(0.to_d)
      user.expense_entries
        .paid
        .where.not(category: [ nil, "" ])
        .where(occurred_on: period_date_range)
        .find_each do |entry|
          next if entry.income?

          totals[entry.category] += entry.effective_amount.to_d
        end
      totals.sort_by { |_category, amount| -amount }
    end

    def target_category_totals
      totals = Hash.new(0.to_d)
      closed_category_totals.each { |category, amount| totals[category] += amount }
      open_category_totals.each { |category, amount| totals[category] += amount }
      totals.sort_by { |_category, amount| -amount }
    end

    def closed_category_totals
      return {} if active_closes_by_period_id.empty?

      workspace.month_close_transaction_snapshots
        .where(month_close_id: active_closes_by_period_id.values.map(&:id), flow_kind: "outflow")
        .group(:category_snapshot)
        .sum(:gross_amount)
    end

    def open_category_totals
      starts = open_periods.map(&:starts_on)
      return {} if starts.empty?

      workspace.financial_transactions
        .state_posted
        .flow_kind_outflow
        .where(effective_on: starts.min..starts.max.end_of_month)
        .where("DATE_TRUNC('month', financial_transactions.effective_on)::date IN (?)", starts)
        .left_joins(:category)
        .group("COALESCE(categories.name, 'Uncategorized')")
        .sum(:gross_amount)
    end

    def period_date_range
      return Date.current.beginning_of_year..Date.current if period_rows_months.empty?

      period_rows_months.first.month_on..period_rows_months.last.month_on.end_of_month
    end

    def mapped_periods_by_month_id
      @mapped_periods_by_month_id ||= begin
        month_ids = period_rows_months.map(&:id)
        mappings = workspace.legacy_record_mappings.where(
          legacy_record_type: "BudgetMonth",
          legacy_record_id: month_ids,
          target_record_type: "BudgetPeriod"
        ).pluck(:legacy_record_id, :target_record_id).to_h
        periods = workspace.budget_periods.where(id: mappings.values).index_by(&:id)
        mapped = mappings.transform_values { |period_id| periods[period_id] }.compact
        missing = period_rows_months.reject { |month| mapped.key?(month.id) }
        if missing.any?
          raise ActiveRecord::RecordNotFound, "Target period mapping is missing for #{missing.map(&:label).join(', ')}"
        end

        mapped
      end
    end

    def active_closes_by_period_id
      @active_closes_by_period_id ||= workspace.month_closes
        .state_closed
        .where(budget_period_id: mapped_periods_by_month_id.values.map(&:id))
        .index_by(&:budget_period_id)
    end

    def open_periods
      @open_periods ||= mapped_periods_by_month_id.values.reject do |period|
        active_closes_by_period_id.key?(period.id)
      end
    end

    def live_target_summaries
      @live_target_summaries ||= Budgeting::PeriodSummaryBatch.call(periods: open_periods)
    end

    def period_rows_months
      @period_rows_months ||= user.budget_months.recent_first.limit(12).to_a.reverse
    end

    def workspace
      @workspace ||= BudgetWorkspace.find_by(legacy_owner_user_id: user.id)
    end

    def target_reads?
      workspace&.target_reads_enabled?
    end

    def routes
      Rails.application.routes.url_helpers
    end
  end
end
