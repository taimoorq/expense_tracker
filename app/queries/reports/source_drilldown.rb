module Reports
  class SourceDrilldown
    MAX_RANGE = 13.months
    Row = Data.define(:id, :effective_on, :description, :amount, :source_label, :month_label, :detail_path)
    Result = Data.define(:category, :starts_on, :ends_on, :rows, :total, :calculation_version)

    def self.call(user:, category:, starts_on:, ends_on:)
      new(user: user, category: category, starts_on: starts_on, ends_on: ends_on).call
    end

    def initialize(user:, category:, starts_on:, ends_on:)
      @user = user
      @category = category.to_s.presence || "Uncategorized"
      @starts_on = parse_date(starts_on) || Date.current.beginning_of_year
      @ends_on = parse_date(ends_on) || Date.current
      raise ArgumentError, "The report source range is invalid." if @ends_on < @starts_on || @ends_on > @starts_on + MAX_RANGE
    end

    def call
      rows = target_reads? ? target_rows : legacy_rows
      Result.new(
        category: category,
        starts_on: starts_on,
        ends_on: ends_on,
        rows: rows,
        total: rows.sum(&:amount),
        calculation_version: target_reads? ? "target-v1" : "legacy-compatible-v1"
      )
    end

    private

    attr_reader :category, :ends_on, :starts_on, :user

    def target_rows
      (closed_snapshot_rows + live_rows).sort_by { |row| [ row.effective_on, row.id ] }.reverse
    end

    def closed_snapshot_rows
      workspace.month_close_transaction_snapshots
        .joins(month_close: :budget_period)
        .merge(MonthClose.state_closed)
        .where(flow_kind: "outflow", category_snapshot: category, effective_on: starts_on..ends_on)
        .includes(month_close: :budget_period)
        .map do |snapshot|
          Row.new(
            id: snapshot.id,
            effective_on: snapshot.effective_on,
            description: snapshot.description_snapshot,
            amount: snapshot.gross_amount,
            source_label: "Closed snapshot",
            month_label: snapshot.month_close.budget_period.starts_on.strftime("%B %Y"),
            detail_path: routes.activity_path(view: "all", transaction_id: snapshot.financial_transaction_id)
          )
        end
    end

    def live_rows
      starts = open_period_starts
      return [] if starts.empty?

      workspace.financial_transactions
        .state_posted
        .flow_kind_outflow
        .where(effective_on: starts_on..ends_on)
        .where("DATE_TRUNC('month', financial_transactions.effective_on)::date IN (?)", starts)
        .left_joins(:category)
        .where("COALESCE(categories.name, 'Uncategorized') = ?", category)
        .order(effective_on: :desc, created_at: :desc)
        .map do |transaction|
          Row.new(
            id: transaction.id,
            effective_on: transaction.effective_on,
            description: transaction.description,
            amount: transaction.gross_amount,
            source_label: "Live target data",
            month_label: transaction.effective_on.strftime("%B %Y"),
            detail_path: routes.activity_path(view: "all", transaction_id: transaction.id)
          )
        end
    end

    def legacy_rows
      scope = user.expense_entries
        .paid
        .where(occurred_on: starts_on..ends_on, category: category)
        .where.not(section: ExpenseEntry.sections.fetch("income"))
        .includes(:budget_month)
        .order(occurred_on: :desc, created_at: :desc)
      scope.map do |entry|
        Row.new(
          id: entry.id,
          effective_on: entry.occurred_on,
          description: entry.payee.presence || entry.category,
          amount: entry.effective_amount,
          source_label: "Live legacy data",
          month_label: entry.budget_month.label,
          detail_path: routes.budget_month_tab_path(entry.budget_month, "entries", anchor: "entry-#{entry.id}")
        )
      end
    end

    def open_period_starts
      @open_period_starts ||= begin
        periods = workspace.budget_periods.where(starts_on: starts_on.beginning_of_month..ends_on.beginning_of_month)
        closed_ids = workspace.month_closes.state_closed.where(budget_period_id: periods.select(:id)).pluck(:budget_period_id)
        periods.where.not(id: closed_ids).pluck(:starts_on)
      end
    end

    def workspace
      @workspace ||= user.legacy_owned_budget_workspace
    end

    def target_reads?
      workspace&.target_reads_enabled?
    end

    def parse_date(value)
      Date.iso8601(value.to_s) if value.present?
    rescue Date::Error
      nil
    end

    def routes
      Rails.application.routes.url_helpers
    end
  end
end
