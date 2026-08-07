module Budgeting
  class EntryWizardPresenter
    attr_reader :budget_month, :expense_entry

    def initialize(budget_month:, expense_entry:, params:)
      @budget_month = budget_month
      @expense_entry = expense_entry
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

    def selected_ends_on
      @template_params[:ends_on]
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

    def selected_source_mode
      return "existing" if selected_recurring_link.present?

      @params[:source_mode].presence_in(%w[one_time existing]) || "one_time"
    end

    def recurring_choice_groups
      @recurring_choice_groups ||= recurring_group_definitions.filter_map do |label, records|
        choices = records.map { |record| recurring_choice(record) }
        [ label, choices ] if choices.any?
      end
    end

    def initial_impact
      Budgeting::EntryComposerImpact.call(expense_entry: expense_entry, budget_month: budget_month)
    end

    def template_type_options
      [
        [ "Choose what should repeat", "" ],
        *Recurring::TemplateCatalog.wizard_template_types.map { |type| [ recurring_template_type_label(type), type ] }
      ]
    end

    def supported_template_types_by_section
      @supported_template_types_by_section ||= begin
        supported = ExpenseEntry.sections.keys.index_with { [] }

        Recurring::TemplateCatalog.wizard_models.each do |model|
          model.template_wizard_sections.each do |section|
            supported[section] << model.template_type_key.to_s
          end
        end

        supported
      end
    end

    def billing_month_counts_by_frequency
      MonthlyBill::BILLING_MONTHS_BY_FREQUENCY.transform_values(&:count)
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

    def recurring_group_definitions
      user = budget_month.user

      [
        [ "Pay schedules", user.pay_schedules.active_during_month(budget_month.month_on).includes(:linked_account).to_a ],
        [ "Subscriptions", user.subscriptions.active_only.includes(:linked_account).to_a ],
        [ "Bills", user.monthly_bills.active_only.includes(:linked_account).to_a ],
        [ "Payment plans", user.payment_plans.active_only.includes(:linked_account).to_a ],
        [ "Credit cards", user.credit_cards.active_only.includes(:linked_account, :payment_account).to_a ]
      ]
    end

    def recurring_choice(record)
      month_status = Recurring::TemplateMonthStatus.call(
        template: record,
        budget_month: budget_month,
        entries: budget_month.expense_entries.to_a
      )

      {
        token: "#{record.class.name}:#{record.id}",
        name: record.name,
        status: month_status.status.to_s,
        status_label: month_status.label,
        extra_occurrence_required: month_status.extra_occurrence_required?,
        prefill: month_status.prefill
      }
    end

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

    def recurring_template_type_label(type)
      {
        "pay_schedule" => "Pay schedule",
        "subscription" => "Subscription",
        "monthly_bill" => "Bill",
        "payment_plan" => "Payment plan"
      }.fetch(type.to_s, type.to_s.humanize)
    end
  end
end
