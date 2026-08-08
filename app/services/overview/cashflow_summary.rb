module Overview
  class CashflowSummary
    def initialize(user:, year:)
      @user = user
      @year = year
    end

    def call
      {
        overview_cashflow_year: year,
        year_budget_months: year_budget_months,
        year_cashflow_payload: target_payload || legacy_payload
      }
    end

    private

    attr_reader :user, :year

    def target_payload
      @target_payload ||= Budgeting::TargetYearCashflowSankey.for(
        user: user,
        year: year,
        budget_months: year_budget_months
      )
    end

    def legacy_payload
      Budgeting::YearCashflowSankey.cached_payload(
        user: user,
        year: year,
        budget_months: year_budget_months
      )
    end

    def year_budget_months
      @year_budget_months ||= user.budget_months
        .where(month_on: Date.new(year, 1, 1)..Date.new(year, 12, 31))
        .includes(:expense_entries)
        .order(:month_on)
        .to_a
    end
  end
end
