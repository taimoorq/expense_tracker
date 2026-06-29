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
      target_month = target_budget_month_for(permitted[:occurred_on]) if permitted.key?(:occurred_on)
      return false if target_month == :missing

      permitted[:budget_month] = target_month if target_month.present?
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

    def target_budget_month_for(occurred_on_value)
      occurred_on = parse_date(occurred_on_value)
      return nil if occurred_on.blank?

      target_month_on = occurred_on.beginning_of_month
      current_month_on = expense_entry.budget_month.month_on.to_date.beginning_of_month
      return nil if target_month_on == current_month_on

      target_month = expense_entry.user.budget_months.find_by(month_on: target_month_on)
      return target_month if target_month.present?

      expense_entry.errors.add(:occurred_on, missing_month_message(target_month_on))
      :missing
    end

    def parse_date(value)
      return value if value.is_a?(Date)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    def missing_month_message(target_month_on)
      current_month_on = expense_entry.budget_month.month_on.to_date.beginning_of_month
      current_range = "#{current_month_on.strftime("%B %-d")} through #{current_month_on.end_of_month.strftime("%B %-d")}"
      target_label = target_month_on.strftime("%B %Y")

      "is outside #{expense_entry.budget_month.label}. Create #{target_label} first, or choose a date from #{current_range}."
    end
  end
end
