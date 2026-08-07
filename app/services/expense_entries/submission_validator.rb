module ExpenseEntries
  class SubmissionValidator
    def self.call(expense_entry:, planning_template_params:, recurring_link_token:)
      new(
        expense_entry: expense_entry,
        planning_template_params: planning_template_params,
        recurring_link_token: recurring_link_token
      ).call
    end

    def initialize(expense_entry:, planning_template_params:, recurring_link_token:)
      @expense_entry = expense_entry
      @planning_template_params = planning_template_params.to_h.with_indifferent_access
      @recurring_link_token = recurring_link_token.to_s
    end

    def call
      errors.add(:occurred_on, "choose a date") if expense_entry.occurred_on.blank?
      errors.add(:category, "choose a category") if expense_entry.category.blank?
      errors.add(:payee, "enter who this is with") if expense_entry.payee.blank?
      errors.add(:amount, "enter a planned or actual amount") if amounts_blank?
      errors.add(:recurring_transaction, "choose an existing recurring item or create a new one, not both") if recurring_choices_conflict?
      errors.add(:recurring_transaction, unsupported_destination_message) if new_template_loses_destination?

      errors.none?
    end

    private

    attr_reader :expense_entry, :planning_template_params, :recurring_link_token

    delegate :errors, to: :expense_entry

    def amounts_blank?
      expense_entry.planned_amount.blank? && expense_entry.actual_amount.blank?
    end

    def recurring_choices_conflict?
      recurring_link_token.present? && ActiveModel::Type::Boolean.new.cast(planning_template_params[:enabled])
    end

    def new_template_loses_destination?
      expense_entry.destination_account_id.present? && ActiveModel::Type::Boolean.new.cast(planning_template_params[:enabled])
    end

    def unsupported_destination_message
      "cannot carry the Money goes to account for a new recurring item; save this as one-time or link an existing credit card"
    end
  end
end
