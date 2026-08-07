module ExpenseEntries
  class Updater
    def self.call(expense_entry:, params:, mark_as_paid:)
      new(expense_entry: expense_entry, params: params, mark_as_paid: mark_as_paid).call
    end

    def initialize(expense_entry:, params:, mark_as_paid:)
      @expense_entry = expense_entry
      @params = params
      @mark_as_paid = mark_as_paid
    end

    def call
      permitted = normalized_params
      month_result = month_result_for(permitted[:occurred_on]) if permitted.key?(:occurred_on)
      unless month_result.nil? || month_result.success?
        expense_entry.errors.add(:occurred_on, month_result.error_message)
        return false
      end

      permitted[:budget_month] = month_result.budget_month if month_result.present?
      expense_entry.update(permitted)
    end

    private

    attr_reader :expense_entry, :params, :mark_as_paid

    def normalized_params
      permitted = params.to_h.symbolize_keys
      permitted[:auto_completed_at] = nil if expense_entry.auto_completed?
      return permitted unless mark_as_paid

      permitted[:status] = "paid"
      permitted[:actual_amount] = permitted[:planned_amount].presence || expense_entry.planned_amount if permitted[:actual_amount].blank?
      permitted
    end

    def month_result_for(occurred_on_value)
      MonthResolver.call(
        user: expense_entry.user,
        current_month: expense_entry.budget_month,
        occurred_on: occurred_on_value,
        allow_move: true
      )
    end
  end
end
