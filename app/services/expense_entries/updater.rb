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
      expense_entry.update(normalized_params)
    end

    private

    attr_reader :expense_entry, :params, :mark_as_paid

    def normalized_params
      permitted = params.to_h.symbolize_keys
      return permitted unless mark_as_paid

      permitted[:status] = "paid"
      permitted[:actual_amount] = permitted[:planned_amount].presence || expense_entry.planned_amount if permitted[:actual_amount].blank?
      permitted
    end
  end
end
