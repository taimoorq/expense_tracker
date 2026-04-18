module Budgeting
  class MonthFormState
    Result = Data.define(
      :cloneable_budget_months,
      :cloneable_month_options,
      :source_budget_month,
      :clone_preview,
      :month_workflow,
      :wizard_step,
      :include_applicable_templates,
      :new_month_defaults
    )

    def self.call(user:, params:)
      new(user: user, params: params).call
    end

    def initialize(user:, params:)
      @user = user
      @params = params
    end

    def call
      Result.new(
        cloneable_budget_months: cloneable_budget_months,
        cloneable_month_options: cloneable_month_options,
        source_budget_month: source_budget_month,
        clone_preview: clone_preview,
        month_workflow: month_workflow,
        wizard_step: wizard_step,
        include_applicable_templates: include_applicable_templates,
        new_month_defaults: new_month_defaults
      )
    end

    private

    attr_reader :user, :params

    def cloneable_budget_months
      @cloneable_budget_months ||= user.budget_months.includes(:expense_entries).recent_first.to_a
    end

    def cloneable_month_options
      @cloneable_month_options ||= cloneable_budget_months.map do |month|
        target_month = next_available_month_after(month.month_on)

        {
          id: month.id,
          source_label: month.label,
          target_label: target_month.strftime("%B %Y"),
          entry_count: month.expense_entries.size
        }
      end
    end

    def source_budget_month
      @source_budget_month ||= user.budget_months.find_by(id: params[:source_month_id])
    end

    def clone_preview
      cloneable_month_options.find { |option| option[:id] == source_budget_month&.id }
    end

    def month_workflow
      return "fresh" if cloneable_budget_months.empty?

      params[:month_workflow].presence_in(%w[fresh clone]) || (source_budget_month.present? ? "clone" : "fresh")
    end

    def wizard_step
      return 1 if cloneable_budget_months.empty?

      params[:wizard_step].to_i
    end

    def include_applicable_templates
      return params[:include_applicable_templates] == "1" if params.key?(:include_applicable_templates)
      return false if month_workflow == "clone"

      true
    end

    def new_month_defaults
      return {} unless source_budget_month

      clone_month_attributes(source_budget_month).slice(:month_on, :label)
    end

    def clone_month_attributes(source_month)
      target_month = next_available_month_after(source_month.month_on)

      {
        month_on: target_month,
        label: target_month.strftime("%B %Y"),
        notes: source_month.notes
      }
    end

    def next_available_month_after(month_on)
      target_month = month_on.next_month.beginning_of_month

      while user.budget_months.exists?(month_on: target_month)
        target_month = target_month.next_month.beginning_of_month
      end

      target_month
    end
  end
end
