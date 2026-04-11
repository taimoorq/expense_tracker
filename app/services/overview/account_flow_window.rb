module Overview
  class AccountFlowWindow
    MONTH_WINDOW_OPTIONS = [
      [ "Last month", "1" ],
      [ "Last 3 months", "3" ],
      [ "Last 6 months", "6" ],
      [ "Last 12 months", "12" ],
      [ "All saved months", "all" ]
    ].freeze
    DEFAULT_MONTH_WINDOW = "3"

    def initialize(user:, month_window: DEFAULT_MONTH_WINDOW)
      @user = user
      @month_window = normalized_month_window(month_window)
    end

    def call
      {
        account_flow_month_window: month_window,
        account_flow_months_included: selected_budget_months.count,
        account_flow_month_range_label: month_range_label,
        account_flow_payload: Accounts::AccountFlowSummary.new(expense_entries: selected_expense_entries).payload
      }
    end

    private

    attr_reader :month_window, :user

    def normalized_month_window(raw_value)
      value = raw_value.to_s
      return value if MONTH_WINDOW_OPTIONS.any? { |_label, option_value| option_value == value }

      DEFAULT_MONTH_WINDOW
    end

    def selected_budget_months
      @selected_budget_months ||= begin
        months = user.budget_months.includes(expense_entries: [ :source_account, :source_template ]).recent_first.to_a
        month_window == "all" ? months : months.first(month_window.to_i)
      end
    end

    def selected_expense_entries
      @selected_expense_entries ||= selected_budget_months.flat_map(&:expense_entries)
    end

    def month_range_label
      return "No saved months yet" if selected_budget_months.empty?

      ordered_months = selected_budget_months.sort_by(&:month_on)
      return ordered_months.first.label if ordered_months.one?

      "#{ordered_months.first.label} to #{ordered_months.last.label}"
    end
  end
end
