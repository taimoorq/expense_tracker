module Budgeting
  class MonthAccountFlowSummary
    def self.cached_payload(budget_month:, expense_entries: nil)
      expense_entries ||= fresh_expense_entries(budget_month)

      Rails.cache.fetch(cache_key_for(budget_month: budget_month, expense_entries: expense_entries), expires_in: 12.hours) do
        new(budget_month: budget_month, expense_entries: expense_entries).payload
      end
    end

    def initialize(budget_month:, expense_entries: nil)
      @budget_month = budget_month
      @expense_entries = expense_entries || self.class.send(:fresh_expense_entries, budget_month)
      @entries = @expense_entries.to_a
    end

    def payload
      Accounts::AccountFlowSummary.new(expense_entries: entries).payload
    end

    private

    attr_reader :budget_month, :expense_entries, :entries

    def self.fresh_expense_entries(budget_month)
      budget_month.expense_entries.reset
    end
    private_class_method :fresh_expense_entries

    def self.cache_key_for(budget_month:, expense_entries:)
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
        "account_flow",
        budget_month.cache_key_with_version,
        relation_count,
        relation_updated_at&.utc&.iso8601(6)
      ]
    end
  end
end
