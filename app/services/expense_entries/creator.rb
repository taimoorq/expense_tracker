module ExpenseEntries
  class Creator
    Result = Data.define(:success?, :expense_entry, :message)

    def self.call(user:, budget_month:, expense_entry_params:, planning_template_params:, recurring_link_token:)
      new(
        user: user,
        budget_month: budget_month,
        expense_entry_params: expense_entry_params,
        planning_template_params: planning_template_params,
        recurring_link_token: recurring_link_token
      ).call
    end

    def initialize(user:, budget_month:, expense_entry_params:, planning_template_params:, recurring_link_token:)
      @user = user
      @budget_month = budget_month
      @expense_entry_params = expense_entry_params
      @planning_template_params = planning_template_params
      @recurring_link_token = recurring_link_token.to_s
    end

    def call
      expense_entry = budget_month.expense_entries.new(expense_entry_params)
      assign_selected_recurring_source(expense_entry)
      template_creator = Recurring::EntryWizardTemplateCreator.new(user: user, expense_entry: expense_entry, params: planning_template_params)
      saved_successfully = false

      ActiveRecord::Base.transaction do
        if expense_entry.errors.none? && expense_entry.save
          if template_creator.save
            saved_successfully = true
          else
            template_creator.error_messages.each { |message| expense_entry.errors.add(:base, message) }
            raise ActiveRecord::Rollback
          end
        end
      end

      expense_entry = rebuilt_failed_entry(expense_entry) unless saved_successfully
      message = template_creator.requested? ? "Entry and recurring transaction added." : "Entry added."
      Result.new(success?: saved_successfully, expense_entry: expense_entry, message: message)
    end

    private

    attr_reader :user, :budget_month, :expense_entry_params, :planning_template_params, :recurring_link_token

    def assign_selected_recurring_source(expense_entry)
      return if recurring_link_token.blank?

      recurring_source = Recurring::TemplateCatalog.user_record_from_token(user: user, token: recurring_link_token)
      if recurring_source.present?
        expense_entry.source_template = recurring_source
      else
        expense_entry.errors.add(:base, "Choose a valid recurring transaction to link.")
      end
    end

    def rebuilt_failed_entry(expense_entry)
      return expense_entry unless expense_entry.persisted?

      failed_errors = expense_entry.errors.dup
      rebuilt_entry = budget_month.expense_entries.new(expense_entry_params)
      failed_errors.each { |error| rebuilt_entry.errors.add(error.attribute, error.message) }
      rebuilt_entry
    end
  end
end
