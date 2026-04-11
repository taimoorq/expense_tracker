module Budgeting
  class EntryWizardPresenter
    attr_reader :budget_month, :expense_entry, :wizard_steps

    def initialize(budget_month:, expense_entry:, params:, wizard_steps:)
      @budget_month = budget_month
      @expense_entry = expense_entry
      @wizard_steps = wizard_steps
      @params = normalize_params(params)
      @template_params = @params.fetch(:planning_template, {})
    end

    def template_enabled?
      ActiveModel::Type::Boolean.new.cast(@template_params[:enabled])
    end

    def selected_template_type
      @template_params[:template_type].to_s
    end

    def selected_due_day
      @template_params[:due_day].presence || expense_entry.occurred_on&.day
    end

    def selected_day_of_month_one
      @template_params[:day_of_month_one].presence || expense_entry.occurred_on&.day
    end

    def selected_day_of_month_two
      @template_params[:day_of_month_two]
    end

    def selected_total_due
      @template_params[:total_due]
    end

    def selected_amount_paid
      @template_params[:amount_paid]
    end

    def selected_kind
      @template_params[:kind].presence || "fixed_payment"
    end

    def selected_billing_frequency
      @template_params[:billing_frequency].presence || "monthly"
    end

    def selected_billing_months
      selected_months = Array(@template_params[:billing_months]).reject(&:blank?).map(&:to_i)
      return selected_months if selected_months.any?

      MonthlyBill::BILLING_MONTHS_BY_FREQUENCY.fetch(selected_billing_frequency, (1..12).to_a)
    end

    def selected_cadence
      @template_params[:cadence].presence || "monthly"
    end

    def selected_weekend_adjustment
      @template_params[:weekend_adjustment].presence || "no_adjustment"
    end

    def selected_recurring_link
      @params[:recurring_link].presence || linked_template_token
    end

    def template_type_options
      [
        [ "Choose a recurring transaction type", "" ],
        *Recurring::TemplateCatalog.wizard_template_types.map { |type| [ type.humanize, type ] }
      ]
    end

    def cadence_options
      PaySchedule.cadences.keys.map { |key| [ key.humanize, key ] }
    end

    def weekend_adjustment_options
      PaySchedule.weekend_adjustments.keys.map { |key| [ key.humanize, key ] }
    end

    def billing_frequency_options
      MonthlyBill.billing_frequencies.keys.map { |key| [ key.humanize, key ] }
    end

    def monthly_bill_kind_options
      MonthlyBill.kinds.keys.map { |key| [ key.humanize, key ] }
    end

    def calendar_month_options
      Date::MONTHNAMES.each_with_index.filter_map do |name, index|
        [ name, index ] if index.positive?
      end
    end

    private

    def normalize_params(params)
      source =
        if params.respond_to?(:to_unsafe_h)
          params.to_unsafe_h
        elsif params.respond_to?(:to_h)
          params.to_h
        else
          params
        end

      source.with_indifferent_access
    end

    def linked_template_token
      return if expense_entry.source_template.blank?

      source_template = expense_entry.source_template
      "#{source_template.class.name}:#{source_template.id}"
    end
  end
end
