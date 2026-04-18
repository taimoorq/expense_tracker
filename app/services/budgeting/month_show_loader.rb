module Budgeting
  class MonthShowLoader
    Result = Data.define(:budget_month, :expense_entries, :expense_entry, :previous_budget_month, :next_budget_month)

    def self.call(user:, budget_month:, expense_entry_loader:)
      new(user: user, budget_month: budget_month, expense_entry_loader: expense_entry_loader).call
    end

    def initialize(user:, budget_month:, expense_entry_loader:)
      @user = user
      @budget_month = budget_month
      @expense_entry_loader = expense_entry_loader
    end

    def call
      Result.new(
        budget_month: budget_month,
        expense_entries: expense_entry_loader.call(budget_month.expense_entries.chronological),
        expense_entry: budget_month.expense_entries.new,
        previous_budget_month: user.budget_months.where("month_on < ?", budget_month.month_on).order(month_on: :desc).first,
        next_budget_month: user.budget_months.where("month_on > ?", budget_month.month_on).order(month_on: :asc).first
      )
    end

    private

    attr_reader :user, :budget_month, :expense_entry_loader
  end
end
