module Budgeting
  class MonthIndexLoader
    Result = Data.define(
      :budget_months,
      :selected_year,
      :previous_years,
      :visible_budget_months,
      :planning_template_counts
    )

    def self.call(user:, year_param:)
      new(user: user, year_param: year_param).call
    end

    def initialize(user:, year_param:)
      @user = user
      @year_param = year_param
    end

    def call
      Result.new(
        budget_months: budget_months,
        selected_year: selected_year,
        previous_years: available_years.select { |year| year < current_year },
        visible_budget_months: visible_budget_months,
        planning_template_counts: planning_template_counts
      )
    end

    private

    attr_reader :user, :year_param

    def budget_months
      @budget_months ||= user.budget_months.includes(:expense_entries).recent_first.to_a
    end

    def current_year
      Date.current.year
    end

    def available_years
      @available_years ||= budget_months.map { |month| month.month_on.year }.uniq.sort.reverse
    end

    def selected_year
      @selected_year ||= begin
        candidate = year_param.to_i
        candidate = current_year unless candidate.positive?
        candidate = current_year unless candidate == current_year || available_years.include?(candidate)
        candidate
      end
    end

    def visible_budget_months
      months_for_year = budget_months.select { |month| month.month_on.year == selected_year }
      return months_for_year.sort_by(&:month_on).reverse unless selected_year == current_year

      current_month = Date.current.beginning_of_month
      current_and_past, future = months_for_year.partition { |month| month.month_on <= current_month }
      current_and_past.sort_by(&:month_on).reverse + future.sort_by(&:month_on)
    end

    def planning_template_counts
      {
        pay_schedules: user.pay_schedules.count,
        subscriptions: user.subscriptions.count,
        monthly_bills: user.monthly_bills.count,
        payment_plans: user.payment_plans.count,
        credit_cards: user.credit_cards.count
      }
    end
  end
end
