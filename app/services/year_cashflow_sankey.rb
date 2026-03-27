class YearCashflowSankey
  DEFAULT_CATEGORY_LIMIT = 10

  def self.cached_payload(user:, year:, budget_months: scoped_budget_months(user:, year:), category_limit: DEFAULT_CATEGORY_LIMIT)
    Rails.cache.fetch(cache_key_for(user:, year:, budget_months:, category_limit:), expires_in: cache_expiry_for(year)) do
      new(user:, year:, budget_months:, category_limit:).payload
    end
  end

  def self.scoped_budget_months(user:, year:)
    user.budget_months
      .where(month_on: Date.new(year, 1, 1)..Date.new(year, 12, 31))
      .includes(:expense_entries)
      .order(:month_on)
  end

  def initialize(user:, year:, budget_months: self.class.scoped_budget_months(user:, year:), category_limit: DEFAULT_CATEGORY_LIMIT)
    @user = user
    @year = year
    @budget_months = budget_months.to_a
    @entries = @budget_months.flat_map { |month| month.expense_entries.to_a }
    @category_limit = category_limit
  end

  def payload
    {
      year: year,
      month_count: budget_months.size,
      nodes: node_names.map { |name| { name: name } },
      links: links,
      income_total: income_total.round(2),
      outflow_total: outflow_total.round(2),
      leftover_total: leftover_total.round(2),
      limitations: limitations
    }
  end

  private

  attr_reader :user, :year, :budget_months, :entries, :category_limit

  def self.cache_key_for(user:, year:, budget_months:, category_limit:)
    months = budget_months.to_a
    month_ids = months.map(&:id).sort
    month_updated_at = months.filter_map(&:updated_at).max
    entry_updated_at = months.flat_map { |month| month.expense_entries.to_a }.filter_map(&:updated_at).max
    entry_count = months.sum { |month| month.expense_entries.size }

    [
      "users",
      user.id,
      "year_cashflow_graph",
      year,
      month_ids,
      month_updated_at&.utc&.iso8601(6),
      entry_count,
      entry_updated_at&.utc&.iso8601(6),
      category_limit
    ]
  end

  def self.cache_expiry_for(year)
    year < Date.current.year ? 30.days : 1.hour
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
    @leftover_total ||= income_total - outflow_total
  end

  def income_node_name
    "#{year} Income"
  end

  def leftover_node_name
    "#{year} Leftover"
  end

  def node_names
    @node_names ||= begin
      names = []
      names.concat(income_breakdown.keys)
      names << income_node_name if income_breakdown.any? || category_breakdown.any? || leftover_total.positive?
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
          target: income_node_name,
          value: amount.round(2).to_f
        }
      end

      category_breakdown.each do |category_name, amount|
        next if amount <= 0

        flow_links << {
          source: income_node_name,
          target: category_name,
          value: amount.round(2).to_f
        }
      end

      if leftover_total.positive?
        flow_links << {
          source: income_node_name,
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

  def limitations
    items = []
    items << "This view combines all saved months in #{year}, so it is best for year-to-date flow patterns instead of exact day-to-day timing."
    items << "Categories are grouped from each entry's current category label, so free-form naming can split similar spending into separate nodes."
    items << "Transfers and destination-account flows are still simplified because entries only carry one linked account today."
    items
  end
end
