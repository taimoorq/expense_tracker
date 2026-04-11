module Overview
  class MonthContext
    def initialize(user:, today: Date.current)
      @user = user
      @today = today
    end

    def call
      {
        budget_months: budget_months,
        current_month: current_month,
        recent_months: budget_months.first(4),
        current_month_entries: current_month_entries
      }
    end

    private

    attr_reader :today, :user

    def budget_months
      @budget_months ||= user.budget_months.includes(:expense_entries).recent_first.to_a
    end

    def current_month
      @current_month ||= user.budget_months.find_by(month_on: today.beginning_of_month) || budget_months.first
    end

    def current_month_entries
      @current_month_entries ||= current_month ? current_month.expense_entries.to_a : []
    end
  end
end
