module Budgeting
  class TargetPeriodVisuals
    def self.for(budget_month:)
      workspace = BudgetWorkspace.find_by(legacy_owner_user_id: budget_month.user_id, target_reads_enabled: true)
      return if workspace.blank?

      mapping = workspace.legacy_record_mappings.find_by(
        legacy_record_type: "BudgetMonth",
        legacy_record_id: budget_month.id,
        target_record_type: "BudgetPeriod"
      )
      period = workspace.budget_periods.find_by(id: mapping&.target_record_id)
      new(period: period) if period.present?
    end

    def initialize(period:)
      @period = period
    end

    attr_reader :period

    def calculation_version
      Budgeting::PeriodSummary::CALCULATION_VERSION
    end

    def summary
      @summary ||= Budgeting::PeriodSummary.call(period: period)
    end

    def section_totals
      @section_totals ||= outflow_items
        .group_by(&:budget_group)
        .transform_values { |items| items.sum { |item| forecast_amount(item).to_f }.round(2) }
        .sort_by { |_group, amount| -amount }
        .to_h
    end

    def line_points
      running_points(active_items) do |item|
        item.flow_kind_income? ? forecast_amount(item) : item.flow_kind_outflow? ? -forecast_amount(item) : 0.to_d
      end
    end

    def cumulative_outflow_points
      running_points(outflow_items) { |item| forecast_amount(item) }
    end

    def over_budget_categories
      @over_budget_categories ||= outflow_items
        .group_by { |item| item.category&.name.presence || item.category_snapshot.presence || "Uncategorized" }
        .filter_map do |category, items|
          planned = items.sum(&:planned_amount).to_d
          actual = items.sum { |item| actual_amount(item) }
          variance = actual - planned
          [ category, planned.to_f.round(2), actual.to_f.round(2), variance.to_f.round(2) ] if variance.positive?
        end
        .sort_by { |_category, _planned, _actual, variance| -variance }
        .first(8)
    end

    def sankey_payload
      @sankey_payload ||= begin
        income = aggregate(income_items) { |item| item.payee_snapshot.presence || item.name_snapshot.presence || "Income source" }
        outflow = aggregate(outflow_items) { |item| item.category&.name.presence || item.category_snapshot.presence || item.budget_group.humanize }
        links = income.filter_map do |name, amount|
          { source: name, target: "Income", value: amount.round(2).to_f } if amount.positive?
        end
        links.concat(outflow.filter_map do |name, amount|
          { source: "Income", target: name, value: amount.round(2).to_f } if amount.positive?
        end)
        if summary.forecast_net.positive?
          links << { source: "Income", target: "Forecast remaining", value: summary.forecast_net.round(2).to_f }
        end
        node_names = links.flat_map { |link| [ link[:source], link[:target] ] }.uniq
        {
          nodes: node_names.map { |name| { name: name } },
          links: links,
          income_total: summary.forecast_income.round(2),
          outflow_total: summary.forecast_outflow.round(2),
          leftover_total: summary.forecast_net.round(2),
          limitations: [
            "Open plan items use forecast amounts; matched posted allocations supply actual amounts.",
            "Transfers are excluded from income-to-outflow totals and remain visible in account movement.",
            "Use Activity and the exact-value tables to inspect the records behind these flows."
          ]
        }
      end
    end

    def account_flow_payload
      @account_flow_payload ||= begin
        postings = period.budget_workspace.account_postings
          .joins(:financial_transaction, :account)
          .where(financial_transactions: { state: "posted", effective_on: period.starts_on..period.starts_on.end_of_month })
          .pluck("accounts.id", "accounts.name", "account_postings.amount", "financial_transactions.id")
        grouped = postings.group_by { |account_id, account_name, _amount, _transaction_id| [ account_id, account_name ] }
        rows = grouped.map do |(account_id, account_name), values|
          amounts = values.map { |_id, _name, amount, _transaction_id| amount.to_d }
          {
            id: account_id,
            name: account_name,
            charged_total: amounts.select(&:negative?).sum.abs,
            paid_total: amounts.select(&:positive?).sum,
            transaction_ids: values.map(&:last).uniq
          }
        end.sort_by { |row| -(row[:charged_total] + row[:paid_total]) }
        untracked_count = period.budget_workspace.financial_transactions
          .where(state: "posted", effective_on: period.starts_on..period.starts_on.end_of_month)
          .where.missing(:account_postings)
          .count
        {
          labels: rows.map { |row| row[:name] },
          charged_values: rows.map { |row| row[:charged_total].to_f.round(2) },
          paid_values: rows.map { |row| row[:paid_total].to_f.round(2) },
          charged_total: rows.sum { |row| row[:charged_total] }.round(2),
          paid_total: rows.sum { |row| row[:paid_total] }.round(2),
          account_count: rows.size,
          tracked_entries_count: rows.flat_map { |row| row[:transaction_ids] }.uniq.size,
          untracked_entries_count: untracked_count,
          top_account: rows.first
        }
      end
    end

    private

    def active_items
      @active_items ||= period.budget_items
        .where.not(state: %w[skipped cancelled voided])
        .includes(:category)
        .order(:scheduled_on, :created_at)
        .to_a
    end

    def income_items
      @income_items ||= active_items.select(&:flow_kind_income?)
    end

    def outflow_items
      @outflow_items ||= active_items.select(&:flow_kind_outflow?)
    end

    def allocation_totals
      @allocation_totals ||= period.budget_workspace.budget_allocations
        .joins(:financial_transaction)
        .where(budget_item_id: active_items.map(&:id), financial_transactions: { state: "posted" })
        .group(:budget_item_id)
        .sum(:amount)
    end

    def actual_amount(item)
      allocation_totals.fetch(item.id, 0).to_d
    end

    def forecast_amount(item)
      actual = actual_amount(item)
      actual + [ item.planned_amount - actual, 0 ].max
    end

    def running_points(items)
      items.each_with_object({ labels: [], values: [], running: 0.to_d }) do |item, memo|
        memo[:running] += yield(item)
        memo[:labels] << (item.scheduled_on&.strftime("%b %-d") || "No date")
        memo[:values] << memo[:running].to_f.round(2)
      end.slice(:labels, :values)
    end

    def aggregate(items)
      items.each_with_object(Hash.new(0.to_d)) do |item, totals|
        totals[yield(item)] += forecast_amount(item)
      end
    end
  end
end
