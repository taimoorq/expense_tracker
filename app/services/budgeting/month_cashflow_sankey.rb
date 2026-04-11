module Budgeting
  class MonthCashflowSankey
    DEFAULT_CATEGORY_LIMIT = 8

    def self.cached_payload(budget_month:, expense_entries: nil, category_limit: DEFAULT_CATEGORY_LIMIT)
      expense_entries ||= fresh_expense_entries(budget_month)

      Rails.cache.fetch(cache_key_for(budget_month: budget_month, expense_entries: expense_entries, category_limit: category_limit), expires_in: 12.hours) do
        new(budget_month: budget_month, expense_entries: expense_entries, category_limit: category_limit).payload
      end
    end

    def initialize(budget_month:, expense_entries: nil, category_limit: DEFAULT_CATEGORY_LIMIT)
      @budget_month = budget_month
      @expense_entries = expense_entries || self.class.send(:fresh_expense_entries, budget_month)
      @entries = @expense_entries.to_a
      @category_limit = category_limit
    end

    def payload
      {
        nodes: node_names.map { |name| { name: name } },
        links: links,
        income_total: income_total.round(2),
        outflow_total: outflow_total.round(2),
        leftover_total: leftover_total.round(2),
        limitations: limitations
      }
    end

    private

    attr_reader :budget_month, :expense_entries, :entries, :category_limit

    def self.fresh_expense_entries(budget_month)
      budget_month.expense_entries.reset
    end
    private_class_method :fresh_expense_entries

    def self.cache_key_for(budget_month:, expense_entries:, category_limit:)
      relation_updated_at =
        if expense_entries.respond_to?(:maximum)
          expense_entries.maximum(:updated_at)
        else
          Array(expense_entries).filter_map(&:updated_at).max
        end

      relation_count =
        if expense_entries.respond_to?(:count)
          expense_entries.count
        else
          Array(expense_entries).size
        end

      [
        "budget_months",
        budget_month.id,
        "cashflow_graph",
        budget_month.cache_key_with_version,
        relation_count,
        relation_updated_at&.utc&.iso8601(6),
        category_limit
      ]
    end

    def income_entries
      @income_entries ||= entries.select(&:income?)
    end

    def outflow_entries
      @outflow_entries ||= entries.reject(&:income?)
    end

    def income_total
      @income_total ||= income_entries.sum { |entry| entry.effective_amount.to_d }
    end

    def outflow_total
      @outflow_total ||= outflow_entries.sum { |entry| entry.effective_amount.to_d }
    end

    def leftover_total
      @leftover_total ||= budget_month.calculated_leftover.to_d
    end

    def node_names
      @node_names ||= begin
        names = []
        names.concat(income_breakdown.keys)
        names << "Income"
        names.concat(category_breakdown.keys)
        names << leftover_node_name if leftover_total.positive?
        names.uniq
      end
    end

    def links
      @links ||= begin
        flow_links = []

        income_breakdown.each do |source_name, amount|
          next if amount <= 0

          flow_links << {
            source: source_name,
            target: "Income",
            value: amount.round(2).to_f
          }
        end

        category_breakdown.each do |category_name, amount|
          next if amount <= 0

          flow_links << {
            source: "Income",
            target: category_name,
            value: amount.round(2).to_f
          }
        end

        if leftover_total.positive?
          flow_links << {
            source: "Income",
            target: leftover_node_name,
            value: leftover_total.round(2).to_f
          }
        end

        flow_links
      end
    end

    def income_breakdown
      @income_breakdown ||= aggregate_by_label(income_entries) do |entry|
        entry.payee.presence || entry.category.presence || "Income Source"
      end
    end

    def category_breakdown
      @category_breakdown ||= begin
        grouped = aggregate_by_label(outflow_entries) do |entry|
          normalized_outflow_label(entry)
        end

        top_groups = grouped.sort_by { |_label, amount| -amount }.first(category_limit)
        overflow_amount = grouped.except(*top_groups.map(&:first)).values.sum
        breakdown = top_groups.to_h
        breakdown["Other Outflow"] = overflow_amount if overflow_amount.positive?
        breakdown
      end
    end

    def aggregate_by_label(scope)
      scope.each_with_object(Hash.new(0.to_d)) do |entry, totals|
        label = yield(entry)
        totals[label] += entry.effective_amount.to_d
      end
    end

    def normalized_outflow_label(entry)
      return entry.category.strip if entry.category.present?

      entry.section.humanize
    end

    def leftover_node_name
      "Leftover"
    end

    def limitations
      items = []
      items << "Categories are grouped from each entry's current category label, so free-form naming can split similar spending into separate nodes."
      items << "This view does not yet model transfers from one account into another because entries only carry one linked account today."
      items << "Savings and debt payoff show as outflow buckets or leftover, not as true destination-account flows, until destination accounts are captured on entries."
      items
    end
  end
end
