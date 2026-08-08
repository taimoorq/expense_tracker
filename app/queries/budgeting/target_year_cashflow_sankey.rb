module Budgeting
  class TargetYearCashflowSankey
    DEFAULT_CATEGORY_LIMIT = 10

    def self.for(user:, year:, budget_months:, category_limit: DEFAULT_CATEGORY_LIMIT)
      workspace = BudgetWorkspace.find_by(legacy_owner_user_id: user.id, target_reads_enabled: true)
      return if workspace.blank?

      new(workspace: workspace, year: year, budget_months: budget_months, category_limit: category_limit).payload
    end

    def initialize(workspace:, year:, budget_months:, category_limit: DEFAULT_CATEGORY_LIMIT)
      @workspace = workspace
      @year = year
      @budget_months = Array(budget_months)
      @category_limit = category_limit
    end

    def payload
      {
        year: year,
        month_count: periods.size,
        nodes: node_names.map { |name| { name: name } },
        links: links,
        income_total: income_total.round(2),
        outflow_total: outflow_total.round(2),
        leftover_total: leftover_total.round(2),
        limitations: limitations,
        calculation_version: PeriodSummary::CALCULATION_VERSION
      }
    end

    private

    attr_reader :budget_months, :category_limit, :workspace, :year

    def periods
      @periods ||= begin
        mappings = workspace.legacy_record_mappings.where(
          legacy_record_type: "BudgetMonth",
          legacy_record_id: budget_months.map(&:id),
          target_record_type: "BudgetPeriod"
        ).pluck(:legacy_record_id, :target_record_id).to_h
        periods_by_id = workspace.budget_periods.where(id: mappings.values).index_by(&:id)
        budget_months.filter_map { |month| periods_by_id[mappings[month.id]] }
      end
    end

    def active_items
      @active_items ||= workspace.budget_items
        .where(budget_period_id: periods.map(&:id))
        .where.not(state: %w[skipped cancelled voided])
        .includes(:category)
        .to_a
    end

    def allocation_totals
      @allocation_totals ||= workspace.budget_allocations
        .joins(:financial_transaction)
        .where(budget_item_id: active_items.map(&:id), financial_transactions: { state: "posted" })
        .group(:budget_item_id)
        .sum(:amount)
    end

    def forecast_amount(item)
      actual = allocation_totals.fetch(item.id, 0).to_d
      actual + [ item.planned_amount - actual, 0 ].max
    end

    def income_items
      @income_items ||= active_items.select(&:flow_kind_income?)
    end

    def outflow_items
      @outflow_items ||= active_items.select(&:flow_kind_outflow?)
    end

    def income_total
      @income_total ||= income_items.sum { |item| forecast_amount(item) }
    end

    def outflow_total
      @outflow_total ||= outflow_items.sum { |item| forecast_amount(item) }
    end

    def leftover_total
      @leftover_total ||= income_total - outflow_total
    end

    def income_node_name
      "#{year} Income"
    end

    def leftover_node_name
      "#{year} Forecast Remaining"
    end

    def income_breakdown
      @income_breakdown ||= aggregate(income_items) do |item|
        item.payee_snapshot.presence || item.name_snapshot.presence || "Income source"
      end
    end

    def category_breakdown
      @category_breakdown ||= begin
        grouped = aggregate(outflow_items) do |item|
          item.category&.name.presence || item.category_snapshot.presence || item.budget_group.humanize
        end
        top_groups = grouped.sort_by { |_label, amount| -amount }.first(category_limit)
        overflow = grouped.except(*top_groups.map(&:first)).values.sum
        top_groups.to_h.tap { |values| values["Other Outflow"] = overflow if overflow.positive? }
      end
    end

    def aggregate(items)
      items.each_with_object(Hash.new(0.to_d)) do |item, totals|
        totals[yield(item)] += forecast_amount(item)
      end
    end

    def links
      @links ||= begin
        values = income_breakdown.filter_map do |name, amount|
          { source: name, target: income_node_name, value: amount.round(2).to_f } if amount.positive?
        end
        values.concat(category_breakdown.filter_map do |name, amount|
          { source: income_node_name, target: name, value: amount.round(2).to_f } if amount.positive?
        end)
        if leftover_total.positive?
          values << { source: income_node_name, target: leftover_node_name, value: leftover_total.round(2).to_f }
        end
        values
      end
    end

    def node_names
      @node_names ||= links.flat_map { |link| [ link[:source], link[:target] ] }.uniq
    end

    def limitations
      values = [
        "Open plan items use forecast amounts; matched posted allocations supply actual amounts.",
        "Transfers are excluded from income-to-outflow totals and remain visible in account movement.",
        "Use Reports, Activity, and the exact-value tables to inspect the records behind these flows."
      ]
      missing_count = budget_months.size - periods.size
      values << "#{missing_count} saved #{'month'.pluralize(missing_count)} could not be mapped to a target period." if missing_count.positive?
      values
    end
  end
end
