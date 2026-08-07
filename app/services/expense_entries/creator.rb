module ExpenseEntries
  class Creator
    Result = Data.define(:success?, :expense_entry, :message)

    def self.call(user:, budget_month:, expense_entry_params:, planning_template_params:, recurring_link_token:, recurring_extra_occurrence: nil)
      new(
        user: user,
        budget_month: budget_month,
        expense_entry_params: expense_entry_params,
        planning_template_params: planning_template_params,
        recurring_link_token: recurring_link_token,
        recurring_extra_occurrence: recurring_extra_occurrence
      ).call
    end

    def initialize(user:, budget_month:, expense_entry_params:, planning_template_params:, recurring_link_token:, recurring_extra_occurrence: nil)
      @user = user
      @budget_month = budget_month
      @expense_entry_params = expense_entry_params
      @planning_template_params = planning_template_params
      @recurring_link_token = recurring_link_token.to_s
      @recurring_extra_occurrence = recurring_extra_occurrence
    end

    def call
      expense_entry = budget_month.expense_entries.new(normalized_entry_params)
      assign_selected_recurring_source(expense_entry)
      validate_recurring_coverage(expense_entry)
      validate_month(expense_entry)
      SubmissionValidator.call(
        expense_entry: expense_entry,
        planning_template_params: planning_template_params,
        recurring_link_token: recurring_link_token
      )
      template_creator = Recurring::EntryWizardTemplateCreator.new(user: user, expense_entry: expense_entry, params: planning_template_params)
      saved_successfully = false

      ActiveRecord::Base.transaction do
        if expense_entry.errors.none? && expense_entry.save
          if template_creator.save && link_created_template(expense_entry, template_creator)
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

    attr_reader :user, :budget_month, :expense_entry_params, :planning_template_params, :recurring_link_token, :recurring_extra_occurrence

    def normalized_entry_params
      @normalized_entry_params ||= expense_entry_params.to_h.symbolize_keys.tap do |attributes|
        if attributes[:status].to_s == "paid" && attributes[:actual_amount].blank? && attributes[:planned_amount].present?
          attributes[:actual_amount] = attributes[:planned_amount]
        end
      end
    end

    def validate_month(expense_entry)
      result = MonthResolver.call(
        user: user,
        current_month: budget_month,
        occurred_on: expense_entry.occurred_on,
        allow_move: false
      )
      expense_entry.errors.add(:occurred_on, result.error_message) unless result.success?
    end

    def assign_selected_recurring_source(expense_entry)
      return if recurring_link_token.blank?

      recurring_source = Recurring::TemplateCatalog.user_record_from_token(user: user, token: recurring_link_token)
      if recurring_source.present?
        expense_entry.source_template = recurring_source
      else
        expense_entry.errors.add(:base, "Choose a valid recurring transaction to link.")
      end
    end

    def validate_recurring_coverage(expense_entry)
      return if expense_entry.source_template.blank?

      status = Recurring::TemplateMonthStatus.call(
        template: expense_entry.source_template,
        budget_month: budget_month,
        entries: budget_month.expense_entries.to_a.select(&:persisted?)
      )
      return unless status.extra_occurrence_required?
      return if ActiveModel::Type::Boolean.new.cast(recurring_extra_occurrence)

      expense_entry.errors.add(:recurring_extra_occurrence, "confirm that this is an extra occurrence")
    end

    def link_created_template(expense_entry, template_creator)
      return true unless template_creator.requested?
      return false if template_creator.template_record.blank?

      expense_entry.update(source_template: template_creator.template_record)
    end

    def rebuilt_failed_entry(expense_entry)
      return expense_entry unless expense_entry.persisted?

      failed_errors = expense_entry.errors.dup
      rebuilt_entry = budget_month.expense_entries.new(normalized_entry_params)
      failed_errors.each { |error| rebuilt_entry.errors.add(error.attribute, error.message) }
      rebuilt_entry
    end
  end
end
