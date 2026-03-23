class TemplateTypeRegistry
  TEMPLATE_DEFINITIONS = {
    pay_schedule: {
      model_name: "PaySchedule",
      source_file: "pay_schedule",
      param_key: :pay_schedule,
      recurring_source: true,
      wizard_sections: %w[income],
      permitted_attributes: [ :name, :cadence, :amount, :first_pay_on, :day_of_month_one, :day_of_month_two, :weekend_adjustment, :linked_account_id, :account, :active ]
    },
    subscription: {
      model_name: "Subscription",
      source_file: "subscription",
      param_key: :subscription,
      recurring_source: true,
      wizard_sections: %w[fixed variable manual auto other],
      permitted_attributes: [ :name, :amount, :due_day, :linked_account_id, :account, :active, :notes ]
    },
    monthly_bill: {
      model_name: "MonthlyBill",
      source_file: "monthly_bill",
      param_key: :monthly_bill,
      recurring_source: true,
      wizard_sections: %w[fixed variable manual auto other],
      permitted_attributes: [ :name, :kind, :default_amount, :due_day, :linked_account_id, :account, :active, :notes, :billing_frequency, { billing_months: [] } ]
    },
    payment_plan: {
      model_name: "PaymentPlan",
      source_file: "payment_plan",
      param_key: :payment_plan,
      recurring_source: true,
      wizard_sections: %w[debt manual],
      permitted_attributes: [ :name, :total_due, :amount_paid, :monthly_target, :due_day, :linked_account_id, :account, :active, :notes ]
    },
    credit_card: {
      model_name: "CreditCard",
      source_file: "credit_card_estimate",
      param_key: :credit_card,
      recurring_source: false,
      wizard_sections: [],
      permitted_attributes: [ :name, :minimum_payment, :due_day, :priority, :linked_account_id, :payment_account_id, :account, :active, :notes ]
    }
  }.freeze

  class << self
    def recurring_source_files
      TEMPLATE_DEFINITIONS.values.filter_map do |definition|
        definition[:source_file] if definition[:recurring_source]
      end
    end

    def wizard_template_types
      TEMPLATE_DEFINITIONS.filter_map do |key, definition|
        key.to_s if definition[:wizard_sections].any?
      end
    end

    def wizard_sections_for(template_type)
      definition_for(template_type).fetch(:wizard_sections, [])
    end

    def source_file_for(record_or_type)
      definition_for(record_or_type)&.fetch(:source_file)
    end

    def definition_for(record_or_type)
      return TEMPLATE_DEFINITIONS[record_or_type.to_sym] if record_or_type.respond_to?(:to_sym) && TEMPLATE_DEFINITIONS.key?(record_or_type.to_sym)

      record_class_name = record_or_type.class.name
      TEMPLATE_DEFINITIONS.values.find { |definition| definition[:model_name] == record_class_name }
    end

    def definition_for_source_file(source_file)
      TEMPLATE_DEFINITIONS.values.find { |definition| definition[:source_file] == source_file }
    end
  end
end
